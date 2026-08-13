#!/bin/sh
#
# Consistent database dumps for backrest.
#
# backrest runs this as a CONDITION_SNAPSHOT_START command hook with
# ON_ERROR_FATAL, inside the backrest container, before every snapshot. It
# writes consistent copies of every database it can find into $STAGING_DIR,
# which is then just another path in backrest's backup plan.
#
# Any failure here MUST be fatal. ON_ERROR_FATAL turns a non-zero exit into an
# aborted snapshot, which is the point: a backup that silently contains a torn
# or corrupt dump is worse than no backup at all, because it is only discovered
# to be worthless at restore time. So every step is checked, every dump is
# verified after it is written, and the script exits on the first problem.
#
# ---------------------------------------------------------------------------
# Why there are two mounts of the same data (SQLITE_SCAN_ROOTS / SQLITE_DB_ROOTS)
# ---------------------------------------------------------------------------
#
# Live data is mounted read-only so that a bug in this script cannot damage it:
# every path walked, deleted under, or handed to restic is the read-only one and
# the kernel refuses to write to it.
#
# That is not quite enough for SQLite. Opening a database in WAL mode - even
# purely to read it - requires creating and mapping the "-shm" wal-index file
# next to the database. On a read-only filesystem that fails outright, so a WAL
# database simply cannot be opened from a :ro mount in normal journal mode.
#
# The workaround is a read-write twin of the same volume. On bastion the source
# volumes are mounted at /src (:ro, what gets backed up) and again at /db (rw,
# touched by exactly one thing: a read-only SQLite transaction). SQLITE_DB_ROOTS
# names those twins positionally against SQLITE_SCAN_ROOTS, and for each database
# discovered under a scan root this script prefers the twin copy as its source.
#
# Where no twin is configured, or the twin does not contain that particular file,
# the database is opened with "sqlite3 -readonly" instead. That is a genuine
# fallback and not an equivalent: -readonly only succeeds for databases in
# rollback-journal mode, or WAL databases whose -shm file already exists. A
# WAL-mode database on a truly read-only mount cannot be opened even with
# -readonly, and even when it was cleanly checkpointed and has no -wal file
# beside it, because SQLite still insists on creating the wal-index. Verified:
# it fails with "unable to open database file".
#
# The practical rule that follows: any scan root that can contain WAL databases
# needs either a read-write twin in SQLITE_DB_ROOTS or a read-write mount. When
# that is missing this script fails the whole run loudly rather than skipping the
# database, which is the intended outcome - a silently unbacked-up database is
# the failure mode this design exists to prevent.
#
# Output paths always mirror the SCAN root path regardless of which copy was
# read, so the staging tree is a faithful shadow of the real filesystem:
#   /mnt/containers/vaultwarden/data/db.sqlite3
#     -> $STAGING_DIR/mnt/containers/vaultwarden/data/db.sqlite3
#
# ---------------------------------------------------------------------------
# Environment contract - every block is skipped silently if its primary var is
# unset, so one script serves both hosts.
# ---------------------------------------------------------------------------
#
#   STAGING_DIR              output directory. Default /staging. Its basename
#                            must be "staging"; see clear_staging().
#
#   SQLITE_SCAN_ROOTS        colon-separated dirs scanned recursively for
#                            SQLite databases. Unset => no SQLite handling.
#                            macmini: /mnt/containers   bastion: /src
#   SQLITE_DB_ROOTS          optional colon-separated read-write twins of
#                            SQLITE_SCAN_ROOTS, matched by position.
#                            bastion: /db
#
#   PG_HOST                  set => pg_dump -Fc $PG_DB to
#                            $STAGING_DIR/postgres/$PG_DB.dump
#   PG_PORT                  optional, default 5432
#   PG_USER, PG_PASSWORD, PG_DB
#
#   MYSQL_HOST               set => mariadb-dump each db to
#                            $STAGING_DIR/mysql/<db>.sql
#   MYSQL_PORT               optional, default 3306
#   MYSQL_USER, MYSQL_PASSWORD
#   MYSQL_DBS                space-separated database names
#
#   PORTAINER_URL            set (with PORTAINER_API_KEY) => POST /api/backup to
#                            $STAGING_DIR/portainer/portainer-backup.tar.gz
#   PORTAINER_API_KEY
#   PORTAINER_BACKUP_PASSWORD  optional; empty means an unencrypted archive
#   PORTAINER_INSECURE       optional; any non-empty value passes --insecure,
#                            needed because Portainer serves a self-signed cert
#
# Credentials are never passed as command-line arguments: pg_dump gets
# PGPASSWORD, mariadb-dump gets MYSQL_PWD, and curl reads its API key from a
# 0600 config file. Anything on argv is world-readable through ps.
#
# Deliberately NOT handled: CouchDB.

set -u

STAGING_DIR="${STAGING_DIR:-/staging}"

LIST=/tmp/backrest-sqlite-list
SQLITE_COUNT=0

log() {
	echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
	log "ERROR: $*"
	exit 1
}

# Strip trailing slashes so "/src/" and "/src" produce identical relative paths.
rstrip_slash() {
	_p="$1"
	while :; do
		case "$_p" in
		/) break ;;
		*/) _p="${_p%/}" ;;
		*) break ;;
		esac
	done
	printf '%s' "$_p"
}

# curl config values are double-quoted and understand backslash escapes, so any
# backslash or quote inside a secret has to be escaped or it would terminate the
# value early and silently truncate the credential.
cfg_escape() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# ---------------------------------------------------------------------------
# Staging
# ---------------------------------------------------------------------------
#
# Cleared on every run so that a database which has been deleted from the source
# does not linger in the repository forever, quietly being re-uploaded as if it
# were still live.

clear_staging() {
	# rm -rf against an operator-supplied variable is the single most dangerous
	# line in this script. Refuse anything that is not an absolute path whose
	# last component is literally "staging", which makes it impossible to point
	# this at /src, /mnt/containers, / or an empty string by typo.
	case "$STAGING_DIR" in
	*..*) die "refusing to clear staging path containing '..': $STAGING_DIR" ;;
	/staging | /*/staging) ;;
	*) die "refusing to clear unexpected staging path: $STAGING_DIR (must be /staging or */staging)" ;;
	esac

	mkdir -p "$STAGING_DIR" || die "could not create staging dir $STAGING_DIR"

	log "clearing staging area $STAGING_DIR"
	rm -rf "${STAGING_DIR:?}"/* 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# SQLite
# ---------------------------------------------------------------------------
#
# sqlite3 ".backup" uses SQLite's online backup API. It takes a read
# transaction, copies page by page, and restarts if a writer commits underneath
# it. The result is a genuinely consistent database file, which a plain cp of
# db.sqlite + -wal + -shm is not.
#
# ".backup" is preferred over "VACUUM INTO" because it preserves page numbering,
# so restic deduplicates almost the whole file between runs. VACUUM INTO
# defragments and would upload a mostly-new file every night.
#
# Discovery is recursive and dynamic on purpose: bookhive_social_data holds one
# store.sqlite per PDS actor (158 at time of writing) and gains another on every
# signup. A hardcoded list would silently miss users.

dump_one_sqlite() {
	_src="$1" # what we actually read (rw twin if available)
	_out="$2" # where it goes in staging
	_ro="$3"  # "-readonly" or ""

	mkdir -p "$(dirname "$_out")" || die "mkdir failed for $_out"

	# shellcheck disable=SC2086  # $_ro is an intentional word split
	sqlite3 $_ro "$_src" ".backup '$_out'" || die "sqlite .backup failed: $_src"

	# Prove the snapshot is readable before it is uploaded. A backup that is
	# only discovered to be corrupt at restore time is not a backup.
	sqlite3 "$_out" 'PRAGMA quick_check;' 2>/dev/null | grep -qx ok ||
		die "quick_check failed on snapshot: $_out"
}

scan_sqlite_root() {
	_scan="$(rstrip_slash "$1")"
	_twin="$2"

	[ -d "$_scan" ] || die "SQLITE_SCAN_ROOTS entry is not a directory: $_scan"

	if [ -n "$_twin" ]; then
		_twin="$(rstrip_slash "$_twin")"
		if [ -d "$_twin" ]; then
			log "scanning $_scan (read-write twin: $_twin)"
		else
			log "WARN: read-write twin $_twin does not exist, falling back to -readonly for $_scan"
			_twin=""
		fi
	else
		log "scanning $_scan (no read-write twin, using -readonly)"
	fi

	find "$_scan" \
		\( -name temp -o -name tmp -o -path "$STAGING_DIR" \) -prune -o \
		-type f \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' \) -print \
		>"$LIST" || die "find failed under $_scan"

	# Read from a file rather than a pipe: "find | while" runs the loop in a
	# subshell, where die() would exit only the subshell and let the run carry
	# on to upload an incomplete staging tree.
	while IFS= read -r _f; do
		[ -n "$_f" ] || continue

		# bookhive leaves *.db.pre197 migration artifacts behind; they are dead
		# copies, not live databases.
		case "$_f" in
		*.pre197) continue ;;
		esac

		# If something is named .db but is not a database, fall through and let
		# the normal file backup pick it up as an ordinary file instead of
		# failing the whole run.
		if [ "$(head -c 15 "$_f" 2>/dev/null)" != "SQLite format 3" ]; then
			log "not a sqlite database, leaving to file backup: $_f"
			continue
		fi

		_rel="${_f#"$_scan"/}"

		# Prefer the read-write copy of this exact file so WAL databases can be
		# opened at all; fall back to a read-only open of the :ro mount.
		if [ -n "$_twin" ] && [ -f "$_twin/$_rel" ]; then
			_read_from="$_twin/$_rel"
			_ro=""
		else
			_read_from="$_f"
			_ro="-readonly"
		fi

		dump_one_sqlite "$_read_from" "$STAGING_DIR$_scan/$_rel" "$_ro"

		SQLITE_COUNT=$((SQLITE_COUNT + 1))
	done <"$LIST"

	log "$_scan: done, running total ${SQLITE_COUNT} databases"
}

dump_sqlite() {
	if [ -z "${SQLITE_SCAN_ROOTS:-}" ]; then
		log "SQLITE_SCAN_ROOTS not set, skipping SQLite"
		return 0
	fi

	# Walk both colon-separated lists in lockstep; the Nth db root is the
	# read-write twin of the Nth scan root. A missing entry means "no twin".
	_scan_list="$SQLITE_SCAN_ROOTS"
	_db_list="${SQLITE_DB_ROOTS:-}"

	while [ -n "$_scan_list" ]; do
		case "$_scan_list" in
		*:*)
			_scan_root="${_scan_list%%:*}"
			_scan_list="${_scan_list#*:}"
			;;
		*)
			_scan_root="$_scan_list"
			_scan_list=""
			;;
		esac

		case "$_db_list" in
		"") _db_root="" ;;
		*:*)
			_db_root="${_db_list%%:*}"
			_db_list="${_db_list#*:}"
			;;
		*)
			_db_root="$_db_list"
			_db_list=""
			;;
		esac

		[ -n "$_scan_root" ] || continue
		scan_sqlite_root "$_scan_root" "$_db_root"
	done

	# Setting SQLITE_SCAN_ROOTS is a statement that databases are expected here.
	# Finding none means a mount vanished or a path was mistyped, which would
	# otherwise show up as a cheerfully successful, empty backup.
	[ "$SQLITE_COUNT" -gt 0 ] ||
		die "SQLITE_SCAN_ROOTS is set but no databases were found, refusing to continue"

	log "snapshotted ${SQLITE_COUNT} SQLite databases"
}

# ---------------------------------------------------------------------------
# PostgreSQL
# ---------------------------------------------------------------------------
#
# -Fc is the custom format: compressed, and restorable selectively with
# pg_restore. The dump is a single consistent transaction by construction.

dump_postgres() {
	if [ -z "${PG_HOST:-}" ]; then
		log "PG_HOST not set, skipping PostgreSQL"
		return 0
	fi

	for _v in PG_USER PG_PASSWORD PG_DB; do
		eval "_val=\${${_v}:-}"
		[ -n "$_val" ] || die "PG_HOST is set but ${_v} is not"
	done

	_port="${PG_PORT:-5432}"
	_out="$STAGING_DIR/postgres/${PG_DB}.dump"

	mkdir -p "$(dirname "$_out")" || die "mkdir failed for $_out"

	log "pg_dump ${PG_DB} from ${PG_HOST}:${_port}"

	# PGPASSWORD rather than a URI or --password: argv is visible to every
	# process on the host through ps.
	PGPASSWORD="$PG_PASSWORD" pg_dump \
		--host="$PG_HOST" \
		--port="$_port" \
		--username="$PG_USER" \
		--no-password \
		--format=custom \
		--compress=6 \
		--file="$_out" \
		"$PG_DB" || die "pg_dump failed for ${PG_DB}"

	[ -s "$_out" ] || die "pg_dump produced an empty file: $_out"

	# Reading the archive's table of contents back proves the file is a complete,
	# parseable custom-format dump rather than a truncated one.
	pg_restore --list "$_out" >/dev/null 2>&1 ||
		die "pg_restore --list could not read the dump: $_out"

	log "postgres ${PG_DB}: $(du -h "$_out" | cut -f1)"
}

# ---------------------------------------------------------------------------
# MariaDB / MySQL
# ---------------------------------------------------------------------------
#
# --single-transaction takes the dump inside one repeatable-read transaction, so
# InnoDB tables are mutually consistent without locking the server.

dump_mysql() {
	if [ -z "${MYSQL_HOST:-}" ]; then
		log "MYSQL_HOST not set, skipping MySQL/MariaDB"
		return 0
	fi

	for _v in MYSQL_USER MYSQL_PASSWORD MYSQL_DBS; do
		eval "_val=\${${_v}:-}"
		[ -n "$_val" ] || die "MYSQL_HOST is set but ${_v} is not"
	done

	_port="${MYSQL_PORT:-3306}"
	_dir="$STAGING_DIR/mysql"

	mkdir -p "$_dir" || die "mkdir failed for $_dir"

	# shellcheck disable=SC2086  # MYSQL_DBS is a space-separated list by contract
	for _db in $MYSQL_DBS; do
		_out="$_dir/${_db}.sql"

		log "mariadb-dump ${_db} from ${MYSQL_HOST}:${_port}"

		# MYSQL_PWD rather than --password=, which would expose the password in
		# ps output for the lifetime of the dump.
		MYSQL_PWD="$MYSQL_PASSWORD" mariadb-dump \
			--host="$MYSQL_HOST" \
			--port="$_port" \
			--user="$MYSQL_USER" \
			--single-transaction \
			--quick \
			--routines \
			--events \
			--triggers \
			--default-character-set=utf8mb4 \
			--databases "$_db" >"$_out" || die "mariadb-dump failed for ${_db}"

		[ -s "$_out" ] || die "mariadb-dump produced an empty file: $_out"

		# mariadb-dump writes this trailer only after the last row. Its absence
		# means the stream was cut short even if the exit status was 0.
		tail -c 200 "$_out" | grep -q 'Dump completed' ||
			die "mariadb-dump output is truncated, no completion marker: $_out"

		log "mysql ${_db}: $(du -h "$_out" | cut -f1)"
	done
}

# ---------------------------------------------------------------------------
# Portainer
# ---------------------------------------------------------------------------
#
# Portainer keeps its state in BoltDB, which is memory-mapped and written in
# place. Copying the live portainer.db off disk can therefore capture a torn
# image mid-transaction. /api/backup makes Portainer serialise a consistent
# archive itself, which is the only supported way to export it.

dump_portainer() {
	if [ -z "${PORTAINER_URL:-}" ]; then
		log "PORTAINER_URL not set, skipping Portainer"
		return 0
	fi

	[ -n "${PORTAINER_API_KEY:-}" ] || die "PORTAINER_URL is set but PORTAINER_API_KEY is not"

	_pw="${PORTAINER_BACKUP_PASSWORD:-}"
	_out="$STAGING_DIR/portainer/portainer-backup.tar.gz"

	mkdir -p "$(dirname "$_out")" || die "mkdir failed for $_out"

	_body="$(jq -nc --arg p "$_pw" '{password: $p}')" ||
		die "could not build Portainer request body"

	# Both the API key and the archive password would be visible in ps if passed
	# as -H/-d arguments, so they go into a 0600 config file read with -K.
	_cfg="$(mktemp)" || die "mktemp failed"
	chmod 600 "$_cfg" || die "chmod failed on $_cfg"

	{
		printf 'header = "X-API-Key: %s"\n' "$(cfg_escape "$PORTAINER_API_KEY")"
		printf 'header = "Content-Type: application/json"\n'
		printf 'data = "%s"\n' "$(cfg_escape "$_body")"
	} >"$_cfg" || {
		rm -f "$_cfg"
		die "could not write curl config"
	}

	_insecure=""
	if [ -n "${PORTAINER_INSECURE:-}" ]; then
		_insecure="--insecure"
	fi

	log "requesting Portainer backup from ${PORTAINER_URL}"

	# shellcheck disable=SC2086  # $_insecure is an intentional word split
	curl --silent --show-error --fail --location --max-time 300 \
		--request POST $_insecure \
		--config "$_cfg" \
		--output "$_out" \
		"${PORTAINER_URL}/api/backup"
	_rc=$?

	rm -f "$_cfg"

	[ "$_rc" -eq 0 ] || die "Portainer backup request failed (curl exit ${_rc})"
	[ -s "$_out" ] || die "Portainer returned an empty archive: $_out"

	# An unencrypted archive is a real gzip stream and can be verified. With a
	# password Portainer returns an AES blob, so there is nothing to test.
	if [ -z "$_pw" ]; then
		gzip -t "$_out" 2>/dev/null ||
			die "Portainer archive is not a valid gzip stream: $_out"
	else
		log "archive is password-encrypted, skipping gzip verification"
	fi

	log "portainer: $(du -h "$_out" | cut -f1)"
}

# ---------------------------------------------------------------------------

log "=== database dump starting ==="

clear_staging
dump_sqlite
dump_postgres
dump_mysql
dump_portainer

log "=== database dump complete, staging is $(du -sh "$STAGING_DIR" | cut -f1) ==="
