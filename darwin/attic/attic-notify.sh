# attic-notify - failure and staleness alerting for attic, reusing backrest's mailer.
#
# WHY THIS IS A SEPARATE JOB, NOT A HOOK OR A WRAPPER
# ---------------------------------------------------
# attic v1.0.0-beta.25 has no --on-failure/--on-success hooks (unreleased, on
# main only), so the obvious fix was to wrap `attic backup` in a shell script
# and read its exit status. That is WRONG on macOS and was verified to break:
# TCC attributes a Photos request to the process launchd started, not to the
# one making the request. With a wrapper, tccd logs
#
#   AUTHREQ_ATTRIBUTION: requesting={identifier=attic}, responsible={identifier=bash}
#   AUTHREQ_PROMPTING:   subject={/nix/store/...-bash-5.3p9/bin/bash}
#
# i.e. the backup hangs on a prompt asking to grant Photos access to the *nix
# store bash* - a binary shared by every script on the system. Approving that
# would be both wrong and dangerous; leaving it unapproved hangs the backup
# forever. So attic must be launchd's direct ProgramArguments, and the outcome
# has to be read from outside the run.
#
# launchd already records it: `launchctl print` reports `last exit code` for the
# job, which is authoritative (attic exits non-zero when any asset fails), needs
# no Photos access, and needs no wrapper. This job reads that plus the log's
# mtime, and so covers both failure and the "backups stopped happening at all"
# gap that a failure hook structurally cannot see - the same gap, and the same
# reasoning, as server/backrest/alert-check.sh.
#
# CREDENTIALS
#   The SMTP credential is read out of backrest's own /config/config.json, from
#   the shoutrrr URL of its CONDITION_ANY_ERROR hooks. There stays exactly one
#   copy of the secret per host - rotating it in backrest rotates it here too.
#   jq runs *inside* the container so the config never lands on this host's
#   disk, and credentials reach curl on stdin via `curl -K -`, never on argv and
#   never in a file. Only the non-secret message body is written to a temp file.
#   send_mail/alert/clear_alert are ported from alert-check.sh to keep the two
#   notifiers behaving identically.
#
# Exit status is always 0 unless the script itself is broken.

MODE=${1:-}
STATE_DIR=${ATTIC_ALERT_STATE:-$HOME/.attic/alerts}
STALE_HOURS=${ATTIC_STALE_HOURS:-36}
BACKUP_LABEL=${ATTIC_BACKUP_LABEL:-org.nixos.attic-backup}
BACKUP_LOG=${ATTIC_BACKUP_LOG:-$HOME/Library/Logs/attic/backup.log}
LAUNCHCTL=${ATTIC_LAUNCHCTL:-/bin/launchctl}
REPEAT_HOURS=${ATTIC_ALERT_REPEAT_HOURS:-24}
DRY_RUN=${ATTIC_ALERT_DRY_RUN:-0}
DOCKER=${ATTIC_DOCKER_BIN:-/usr/local/bin/docker}
BACKREST_CONTAINER=${ATTIC_BACKREST_CONTAINER:-backrest}

NOW=$(date -u +%s)
mkdir -p "$STATE_DIR" 2>/dev/null || true

log() { printf '[attic-notify] %s\n' "$*"; }

# backrest's instance name, so subjects line up with backrest's own mail.
INSTANCE=$("$DOCKER" exec "$BACKREST_CONTAINER" \
    jq -r '.instance // "unknown"' /config/config.json 2>/dev/null)
[ -n "$INSTANCE" ] || INSTANCE=unknown

# ------------------------------------------------------------------- mailer
urldecode() {
    # shellcheck disable=SC2059
    printf "$(printf '%s' "$1" | sed 's/%/\\x/g')"
}

SHOUTRRR_URL=$("$DOCKER" exec "$BACKREST_CONTAINER" jq -r \
    '[.repos[]?.hooks[]? | select(.actionShoutrrr) | .actionShoutrrr.shoutrrrUrl] | first // empty' \
    /config/config.json 2>/dev/null)

send_mail() {
    _subject=$1
    _body=$2

    if [ -z "$SHOUTRRR_URL" ]; then
        log "ERROR: no shoutrrr hook readable from container '$BACKREST_CONTAINER'; cannot send mail"
        return 1
    fi

    _rest=${SHOUTRRR_URL#smtp://}
    _userinfo=${_rest%%@*}
    _hostrest=${_rest#*@}
    _hostport=${_hostrest%%/*}
    _query=${SHOUTRRR_URL#*\?}

    _user=$(urldecode "${_userinfo%%:*}")
    _pass=$(urldecode "${_userinfo#*:}")

    _from=$(printf '%s' "$_query" | tr '&' '\n' | sed -n 's/^from=//p'); _from=$(urldecode "$_from")
    _to=$(printf '%s' "$_query"   | tr '&' '\n' | sed -n 's/^to=//p');   _to=$(urldecode "$_to")

    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN: would mail to=$_to subject=$_subject"
        printf '%s\n' "$_body" | sed 's/^/[dry-run] /'
        return 0
    fi

    # Body only - never credentials - goes to a temp file.
    _msg=$(mktemp /tmp/attic-notify-msg.XXXXXX) || return 1
    {
        printf 'From: attic <%s>\n' "$_from"
        printf 'To: %s\n' "$_to"
        printf 'Subject: %s\n' "$_subject"
        printf 'Date: %s\n' "$(date -R 2>/dev/null || date)"
        printf 'MIME-Version: 1.0\nContent-Type: text/plain; charset=utf-8\n\n'
        printf '%s\n' "$_body"
    } > "$_msg"

    # Credentials via stdin (curl -K -), never argv, never a file.
    printf 'url = "smtp://%s"\nuser = "%s:%s"\nmail-from = "%s"\nmail-rcpt = "%s"\nupload-file = "%s"\nssl-reqd\nsilent\nshow-error\n' \
        "$_hostport" "$_user" "$_pass" "$_from" "$_to" "$_msg" \
        | curl -K - >/dev/null 2>&1
    _rc=$?
    rm -f "$_msg"
    if [ $_rc -eq 0 ]; then log "mailed: $_subject"; else log "ERROR: mail send failed rc=$_rc: $_subject"; fi
    return $_rc
}

statefile() { printf '%s/%s' "$STATE_DIR" "$(printf '%s' "$1" | sha256sum | cut -c1-32)"; }

# alert <key> <subject> <body> - deduplicated: re-sends at most every REPEAT_HOURS
alert() {
    _key=$1; _subj=$2; _body=$3
    _sf=$(statefile "$_key")
    _last=0
    if [ -f "$_sf" ]; then
        _last=$(cut -d' ' -f1 < "$_sf" 2>/dev/null)
        case "$_last" in ''|*[!0-9]*) _last=0 ;; esac
    fi
    if [ $((NOW - _last)) -lt $((REPEAT_HOURS * 3600)) ]; then
        log "suppressed (deduplicated, last sent $(((NOW - _last) / 60)) min ago): $_key"
        return 0
    fi
    if send_mail "$_subj" "$_body"; then
        printf '%s %s\n' "$NOW" "$_key" > "$_sf"
    fi
}

# clear_alert <key> <what> - if the key was alerting, send one RESOLVED mail
clear_alert() {
    _key=$1; _what=$2
    _sf=$(statefile "$_key")
    if [ -f "$_sf" ]; then
        rm -f "$_sf"
        send_mail "[attic][$INSTANCE] RESOLVED" "RESOLVED: $_what

Instance : $INSTANCE
Key      : $_key
Time     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')
"
    fi
}

# -------------------------------------------------------------- mode: check
# Reads launchd's own bookkeeping for the backup job rather than wrapping it.
# Two independent conditions, because they fail differently:
#   FAILED - the job ran and exited non-zero (attic exits non-zero when any
#            asset fails to upload, or when the run aborts).
#   STALE  - the job has not produced output in STALE_HOURS. Catches the case a
#            failure signal structurally cannot: the agent not firing at all.
mode_check() {
    _print=$("$LAUNCHCTL" print "gui/$(id -u)/$BACKUP_LABEL" 2>/dev/null)
    if [ -z "$_print" ]; then
        alert "attic-check-degraded" "[attic][$INSTANCE] CHECK DEGRADED" \
"Cannot read launchd job $BACKUP_LABEL.

This is NOT a failure or staleness alert - the check itself is broken. The
agent may be unloaded, or the label may have changed. Try:
  launchctl print gui/\$(id -u)/$BACKUP_LABEL

Instance : $INSTANCE
Time     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')
"
        return 0
    fi
    clear_alert "attic-check-degraded" "the attic backup job is readable again"

    _rc=$(printf '%s' "$_print" | sed -n 's/.*last exit code = \([0-9]*\).*/\1/p' | head -1)

    # Best-effort counters for the alert body. Upstream warns against scraping
    # human output and the summary line is not a stable contract, so a miss
    # degrades to "n/a" rather than failing the check.
    _summary=$(grep -o 'Backup complete: [0-9]* uploaded, [0-9]* failed' "$BACKUP_LOG" 2>/dev/null | tail -1)
    [ -n "$_summary" ] || _summary="(no summary line in $BACKUP_LOG)"

    # --- failure ---
    if [ -n "$_rc" ] && [ "$_rc" != "0" ]; then
        alert "attic-backup-failed" "[attic][$INSTANCE] BACKUP FAILED" \
"The last attic backup exited $_rc.

Instance : $INSTANCE
Exit code: $_rc
Summary  : $_summary
Time     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')

143 means it was terminated (SIGTERM) - usually a darwin-rebuild switch
reloading the agent mid-run, which is harmless: attic is idempotent and the
next run resumes from the manifest and retry queue.

Log: $BACKUP_LOG
"
    else
        clear_alert "attic-backup-failed" "attic backup is succeeding again"
    fi

    # --- staleness, independent of the above ---
    if [ ! -f "$BACKUP_LOG" ]; then
        alert "attic-never-backed-up" "[attic][$INSTANCE] NO BACKUP EVER RAN" \
"No $BACKUP_LOG - the backup agent has never produced output.

Expected during initial setup. If it has been installed more than a day,
investigate.

Instance : $INSTANCE
Time     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')
"
        return 0
    fi
    clear_alert "attic-never-backed-up" "the attic backup job has run"

    # GNU stat (coreutils is on PATH ahead of /usr/bin) and BSD stat spell mtime
    # differently, and GNU `stat -f %m` does not fail on the BSD form - it prints
    # "?" and exits 0, so `cmd || fallback` silently yields garbage. Validate the
    # result is numeric before accepting it, rather than trusting exit status.
    _mtime=$(stat -c %Y "$BACKUP_LOG" 2>/dev/null)
    case "$_mtime" in ''|*[!0-9]*) _mtime=$(stat -f %m "$BACKUP_LOG" 2>/dev/null) ;; esac
    case "$_mtime" in ''|*[!0-9]*)
        log "ERROR: could not read mtime of $BACKUP_LOG"
        return 0 ;;
    esac

    _age_h=$(((NOW - _mtime) / 3600))
    if [ "$_age_h" -ge "$STALE_HOURS" ]; then
        alert "attic-stale" "[attic][$INSTANCE] BACKUP STALE" \
"attic has not written to its log in ${_age_h}h (threshold ${STALE_HOURS}h).

The backup is not failing - it is not running. Check the agent is loaded and
scheduled:
  launchctl print gui/\$(id -u)/$BACKUP_LABEL

Instance : $INSTANCE
Last run : $(date -u -d "@$_mtime" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -r "$_mtime" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)
Age      : ${_age_h}h
Time     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')
"
    else
        log "healthy: last run ${_age_h}h ago, exit code ${_rc:-unknown}"
        clear_alert "attic-stale" "attic backups are current again"
    fi
}

case "$MODE" in
    check) mode_check ;;
    *)
        printf 'usage: attic-notify check\n' >&2
        printf '  check  alert if the last backup exited non-zero, or has not run in %sh\n' "$STALE_HOURS" >&2
        exit 2 ;;
esac
exit 0
