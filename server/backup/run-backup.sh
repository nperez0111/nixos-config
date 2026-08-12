#!/bin/sh
#
# Offsite backup of Docker volumes on bastion -> Backblaze B2 via restic.
#
# Modes:
#   backup  snapshot every SQLite database, upload /staging + /src, then forget
#   prune   reclaim space in the repository (weekly)
#   check   verify repository integrity, reading 5% of the data (monthly)
#   init    create the repository (run once, by hand)
#
# Layout inside the container:
#   /src/<volume>   every source volume, mounted READ-ONLY. restic walks this.
#   /db/<volume>    the same volumes, mounted read-write, used ONLY by sqlite3
#                   because reading a WAL database requires writing the -shm
#                   wal-index. Volumes whose databases are not in WAL mode have
#                   no /db mount at all and are read from /src with -readonly.
#   /staging        consistent database snapshots (a dedicated volume)
#   /cache          restic's repository cache (a dedicated volume)
#
# The split exists so that a bug in this script cannot damage the live data:
# every path this script walks, deletes under, or hands to restic is /src, which
# the kernel refuses to write to. Exactly one command touches /db, and it is a
# read-only SQLite transaction.

set -u

MODE="${1:-backup}"

SRC_ROOT=/src
DB_ROOT=/db
STAGING=/staging
EXCLUDES=/etc/restic-excludes
LIST=/tmp/sqlite-list
BACKUP_LOG=/tmp/restic-backup.json
ERR_LOG=/tmp/restic-stderr

# Snapshots are tagged with a stable host name; the container's own hostname is
# a random hex string that changes on every recreate, which would make
# "restic forget --host" and "restic snapshots --host" useless.
RESTIC_HOST=bastion

OPEN_OBSERVE_URL="${OPEN_OBSERVE_URL:-http://openobserve:5080}"

START_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_EPOCH="$(date +%s)"

DB_COUNT=0
SNAPSHOT_SUMMARY=null

log() {
	echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] $*"
}

# Ship a structured result to OpenObserve. Best-effort: a reporting failure must
# never mask the backup result, so curl failures are logged and swallowed.
report() {
	_status="$1"
	_reason="$2"
	_duration=$(($(date +%s) - START_EPOCH))

	if [ -z "${OPEN_OBSERVE_USER:-}" ] || [ -z "${OPEN_OBSERVE_PASSWORD:-}" ]; then
		log "openobserve credentials not set, skipping report"
		return 0
	fi

	_payload="$(
		jq -n \
			--arg status "$_status" \
			--arg mode "$MODE" \
			--arg reason "$_reason" \
			--arg host "$RESTIC_HOST" \
			--arg started_at "$START_ISO" \
			--argjson duration_seconds "$_duration" \
			--argjson databases_snapshotted "$DB_COUNT" \
			--argjson summary "$SNAPSHOT_SUMMARY" \
			'[{
				event: "restic_backup",
				status: $status,
				mode: $mode,
				reason: $reason,
				host: $host,
				started_at: $started_at,
				duration_seconds: $duration_seconds,
				databases_snapshotted: $databases_snapshotted,
				snapshot_id: ($summary.snapshot_id // null),
				files_new: ($summary.files_new // null),
				files_changed: ($summary.files_changed // null),
				total_files_processed: ($summary.total_files_processed // null),
				total_bytes_processed: ($summary.total_bytes_processed // null),
				data_added: ($summary.data_added // null)
			}]'
	)" || {
		log "WARN: could not build report payload"
		return 0
	}

	if curl -sS -m 30 -u "${OPEN_OBSERVE_USER}:${OPEN_OBSERVE_PASSWORD}" \
		-H 'Content-Type: application/json' \
		-d "$_payload" \
		"${OPEN_OBSERVE_URL}/api/default/backup/_json" >/dev/null; then
		log "reported ${_status} to openobserve"
	else
		log "WARN: failed to report to openobserve"
	fi
}

die() {
	log "ERROR: $*"
	report failure "$*"
	exit 1
}

require_env() {
	for _v in RESTIC_REPOSITORY RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
		eval "_val=\${${_v}:-}"
		[ -n "$_val" ] || die "environment variable ${_v} is not set"
	done
}

# ---------------------------------------------------------------------------
# Phase 1: consistent SQLite snapshots
# ---------------------------------------------------------------------------
#
# sqlite3 ".backup" uses SQLite's online backup API. It takes a read
# transaction, copies page by page, and restarts if a writer commits underneath
# it. The result is a genuinely consistent database file, which a plain cp of
# db.sqlite + -wal + -shm is not.
#
# ".backup" is preferred over "VACUUM INTO" because it preserves page numbering,
# so restic deduplicates almost the entire 1.7 GB file between runs. VACUUM INTO
# defragments and would upload a mostly-new file every night.

snapshot_databases() {
	log "clearing staging area"
	# Guard against a catastrophic typo in the variable above.
	case "$STAGING" in
	/staging) ;;
	*) die "refusing to clear unexpected staging path: $STAGING" ;;
	esac
	rm -rf "${STAGING:?}"/* 2>/dev/null || true

	for _srcdir in "$SRC_ROOT"/*; do
		[ -d "$_srcdir" ] || continue
		_vol="$(basename "$_srcdir")"

		# Prefer the read-write mount so WAL databases can be opened.
		if [ -d "$DB_ROOT/$_vol" ]; then
			_scan="$DB_ROOT/$_vol"
			_ro=""
		else
			_scan="$_srcdir"
			_ro="-readonly"
		fi

		# Discovery is recursive and dynamic on purpose: bookhive_social_data
		# holds one store.sqlite per PDS actor (158 at time of writing) and gains
		# another on every signup. A hardcoded list would silently miss users.
		find "$_scan" \
			\( -name temp -o -name tmp \) -prune -o \
			-type f \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' \) -print \
			>"$LIST" || die "find failed under $_scan"

		# Read from a file rather than a pipe: "find | while" runs the loop in a
		# subshell, where die() would exit the subshell and let the run continue.
		while IFS= read -r _f; do
			[ -n "$_f" ] || continue

			case "$_f" in
			*.pre197) continue ;;
			esac

			# If something is named .db but is not a database, fall through and
			# let restic pick it up as an ordinary file instead of failing.
			if [ "$(head -c 15 "$_f" 2>/dev/null)" != "SQLite format 3" ]; then
				log "not a sqlite database, leaving to file backup: $_f"
				continue
			fi

			_rel="${_f#"$_scan"/}"
			_out="$STAGING/$_vol/$_rel"

			mkdir -p "$(dirname "$_out")" || die "mkdir failed for $_out"

			# shellcheck disable=SC2086  # $_ro is an intentional word split
			sqlite3 $_ro "$_f" ".backup '$_out'" || die "sqlite .backup failed: $_f"

			# Prove the snapshot is readable before it is uploaded. A backup that
			# is only discovered to be corrupt at restore time is not a backup.
			sqlite3 "$_out" 'PRAGMA quick_check;' 2>/dev/null | grep -qx ok ||
				die "quick_check failed on snapshot: $_out"

			DB_COUNT=$((DB_COUNT + 1))
		done <"$LIST"

		log "$_vol: snapshotted, running total ${DB_COUNT} databases"
	done

	[ "$DB_COUNT" -gt 0 ] || die "no databases were snapshotted, refusing to upload"
	log "snapshotted ${DB_COUNT} databases, staging is $(du -sh "$STAGING" | cut -f1)"
}

# ---------------------------------------------------------------------------
# Phase 2: upload
# ---------------------------------------------------------------------------
#
# /src is backed up wholesale minus the exclude patterns rather than as a list
# of known subdirectories, so a new non-database directory appearing in a volume
# is picked up automatically instead of being silently missed.

upload() {
	log "starting restic backup"
	restic backup "$STAGING" "$SRC_ROOT" \
		--host "$RESTIC_HOST" \
		--tag scheduled \
		--exclude-file "$EXCLUDES" \
		--json >"$BACKUP_LOG" 2>"$ERR_LOG" ||
		die "restic backup failed: $(tail -n 5 "$ERR_LOG" | tr '\n' ' ')"

	SNAPSHOT_SUMMARY="$(jq -c 'select(.message_type == "summary")' "$BACKUP_LOG" | tail -n 1)"
	[ -n "$SNAPSHOT_SUMMARY" ] || SNAPSHOT_SUMMARY=null

	if [ "$SNAPSHOT_SUMMARY" != "null" ]; then
		echo "$SNAPSHOT_SUMMARY" | jq -r '
			"snapshot \(.snapshot_id[0:8]): " +
			"\(.total_files_processed) files, " +
			"\(.total_bytes_processed / 1048576 | floor) MiB processed, " +
			"\(.data_added / 1048576 | floor) MiB added, " +
			"\(.total_duration | floor)s"'
	fi
}

forget() {
	log "applying retention policy"
	restic forget \
		--host "$RESTIC_HOST" \
		--keep-daily 14 \
		--keep-weekly 8 \
		--keep-monthly 12 ||
		die "restic forget failed"
}

# ---------------------------------------------------------------------------

case "$MODE" in
init)
	require_env
	log "initialising repository at ${RESTIC_REPOSITORY}"
	restic init || die "restic init failed"
	;;

backup)
	require_env
	log "=== backup run starting ==="
	snapshot_databases
	upload
	forget
	log "=== backup run complete ==="
	report success ""
	;;

prune)
	require_env
	log "=== prune starting ==="
	restic prune || die "restic prune failed"
	log "=== prune complete ==="
	report success ""
	;;

check)
	require_env
	log "=== check starting ==="
	restic check --read-data-subset=5% || die "restic check failed"
	log "=== check complete ==="
	report success ""
	;;

*)
	echo "usage: $0 {backup|prune|check|init}" >&2
	exit 2
	;;
esac
