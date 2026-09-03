#!/bin/sh
# alert-lib.sh - shared mailer and deduplicated alert state.
#
# Sourced (not executed) by alert-check.sh and alert-error.sh so that both
# scripts send mail the same way and keep their state in the same directory.
# Everything here is POSIX sh; the backrest image is Alpine/busybox.
#
# STATE
#   $STATE_DIR/<sha256(key)[:32]>   "<epoch> <key>" - an alert for <key> is
#                                    open; the epoch is when it was last mailed.
#   Callers may keep extra per-key files beside these (alert-error.sh keeps a
#   consecutive-failure counter).
#
# MAIL CREDENTIAL
#   BACKREST_SMTP_URL, a shoutrrr-style smtp:// URL
#     smtp://USER:PASS@HOST:PORT/?from=FROM&to=TO&...
#   set in the Portainer stack Env beside the other secrets dump-databases.sh
#   reads. If unset, fall back to the first actionShoutrrr hook in backrest's
#   config (how it was configured before alert-error.sh replaced that hook).
#   The credential goes to curl on stdin (curl -K -), never argv, never a file.

CFG=${BACKREST_CONFIG:-/config/config.json}
STATE_DIR=${BACKREST_ALERT_STATE:-/data/.backrest-alerts}
REPEAT_HOURS=${BACKREST_ALERT_REPEAT_HOURS:-24}
DRY_RUN=${BACKREST_ALERT_DRY_RUN:-0}
LOG_TAG=${LOG_TAG:-alert}

NOW=$(date -u +%s)
mkdir -p "$STATE_DIR" 2>/dev/null || true

log() { printf '[%s] %s\n' "$LOG_TAG" "$*"; }

INSTANCE=$(jq -r '.instance // "unknown"' "$CFG" 2>/dev/null || echo unknown)

urldecode() {
    # shellcheck disable=SC2059
    printf "$(printf '%s' "$1" | sed 's/%/\\x/g')"
}

SHOUTRRR_URL=${BACKREST_SMTP_URL:-}
if [ -z "$SHOUTRRR_URL" ]; then
    SHOUTRRR_URL=$(jq -r '[.repos[]?.hooks[]? | select(.actionShoutrrr) | .actionShoutrrr.shoutrrrUrl] | first // empty' "$CFG" 2>/dev/null)
fi

send_mail() {
    _subject=$1
    _body=$2

    if [ -z "$SHOUTRRR_URL" ]; then
        log "ERROR: BACKREST_SMTP_URL unset and no shoutrrr hook in $CFG; cannot send mail"
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
    _msg=$(mktemp /tmp/alert-msg.XXXXXX) || return 1
    {
        printf 'From: backrest <%s>\n' "$_from"
        printf 'To: %s\n' "$_to"
        printf 'Subject: %s\n' "$_subject"
        printf 'Date: %s\n' "$(date -R 2>/dev/null || date)"
        printf 'MIME-Version: 1.0\nContent-Type: text/plain; charset=utf-8\n\n'
        printf '%s\n' "$_body"
    } > "$_msg"

    printf 'url = "smtp://%s"\nuser = "%s:%s"\nmail-from = "%s"\nmail-rcpt = "%s"\nupload-file = "%s"\nssl-reqd\nsilent\nshow-error\n' \
        "$_hostport" "$_user" "$_pass" "$_from" "$_to" "$_msg" \
        | curl -K - >/dev/null 2>&1
    _rc=$?
    rm -f "$_msg"
    [ $_rc -eq 0 ] && log "mailed: $_subject" || log "ERROR: mail send failed rc=$_rc: $_subject"
    return $_rc
}

statefile() { printf '%s/%s' "$STATE_DIR" "$(printf '%s' "$1" | sha256sum | cut -c1-32)"; }

# alert <key> <subject> <body>  - deduplicated: re-sends at most every REPEAT_HOURS
alert() {
    _key=$1; _subj=$2; _body=$3
    _sf=$(statefile "$_key")
    _last=0
    if [ -f "$_sf" ]; then
        _last=$(cut -d' ' -f1 < "$_sf" 2>/dev/null)
        case "$_last" in ''|*[!0-9]*) _last=0 ;; esac
    fi
    if [ $((NOW - _last)) -lt $((REPEAT_HOURS * 3600)) ]; then
        log "suppressed (deduplicated, last sent $((( NOW - _last) / 60)) min ago): $_key"
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
        send_mail "[backrest][$INSTANCE] RESOLVED" "RESOLVED: $_what

Instance : $INSTANCE
Key      : $_key
Time     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')
"
    fi
}
