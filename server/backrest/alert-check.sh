#!/bin/sh
# alert-check.sh - active staleness / retention monitoring for backrest.
#
# WHY THIS EXISTS
# ---------------
# backrest can only fire hooks from inside a running task. Its condition enum
# (proto/v1/config.proto, message Hook) has no "a backup did not happen" event,
# and structurally cannot: nothing in backrest observes the passage of time.
# So the repo-level CONDITION_ANY_ERROR shoutrrr hooks catch every *failure*,
# but they are silent when a host simply stops backing up - which is exactly
# how the old bastion crond died (container "Up", nothing ever backed up).
# This script is the active check that closes that gap.
#
# THREE LAYERS
#   A  cross-host liveness. In any repo shared with another backrest instance,
#      take the newest snapshot written by that *instance* (across all of its
#      plans) and alert if it is older than the threshold. Instance-level on
#      purpose: adding/renaming/retiring a plan on the far host can neither
#      create a false alarm nor open a silent gap. This is the layer that
#      survives the other host being dead.
#   B  self plan-level. For every plan in THIS host's own config, check the
#      newest snapshot for plan:<id>,created-by:<self> in that plan's repo.
#      The expected-plan list is read from the live config, so it can never
#      drift. This is the only layer that can see the B2 repos, which are not
#      reachable from the other host.
#   C  retention sanity. Alert if any (plan,instance) has more than
#      BACKREST_MAX_SNAPSHOTS snapshots. This fires even when forget reports
#      success - the symptom of the 8-month stale-lock failure was 7083
#      snapshots, not an error message.
#
# SAFETY
#   * every restic call uses --no-lock: creates no lock files (stale locks were
#     the original root cause) and does not fail while a backup holds the repo.
#   * read-only. This script never calls forget/prune/unlock/backup.
#   * a repo that cannot be reached does NOT raise a staleness alert - we cannot
#     tell "no backups" from "cannot see backups". It increments a per-repo
#     counter and raises a distinct CHECK DEGRADED alert after N consecutive
#     failures, so it neither cries wolf nor goes quiet.
#
# CREDENTIALS
#   Repo passwords/S3 keys and the SMTP credential are all read out of
#   backrest's own /config/config.json (mode 0600). There is exactly one copy of
#   each secret per host. The SMTP credential is reused from the shoutrrr URL of
#   the CONDITION_ANY_ERROR hook, so rotating it in one place rotates it here
#   too. Secrets are passed to curl on stdin via `curl -K -`; only the
#   non-secret message body is ever written to a temp file.
#
# Exit status is always 0 unless the script itself is broken. It is invoked from
# a CONDITION_SNAPSHOT_END hook with onError=ON_ERROR_IGNORE; a non-zero exit
# there would mark an otherwise-good backup as failed and would NOT send mail
# (the SNAPSHOT_END dispatch site does not route through NotifyError).

set -u

CFG=${BACKREST_CONFIG:-/config/config.json}
STATE_DIR=${BACKREST_ALERT_STATE:-/data/.backrest-alerts}
STALE_HOURS=${BACKREST_STALE_HOURS:-36}
MAX_SNAPSHOTS=${BACKREST_MAX_SNAPSHOTS:-120}
REPEAT_HOURS=${BACKREST_ALERT_REPEAT_HOURS:-24}
DEGRADED_AFTER=${BACKREST_DEGRADED_AFTER:-3}
SKIP_IDS=${BACKREST_ALERT_SKIP:-alert-test}
DRY_RUN=${BACKREST_ALERT_DRY_RUN:-0}
RESTIC=${RESTIC_BIN:-/bin/restic}

NOW=$(date -u +%s)
mkdir -p "$STATE_DIR" 2>/dev/null || true

log() { printf '[alert-check] %s\n' "$*"; }

INSTANCE=$(jq -r '.instance // "unknown"' "$CFG")

# ---------------------------------------------------------------- jq helpers
# jq's strptime has no %z, so normalise the numeric offset by hand. Verified
# against +HH:MM, -HH:MM and Z forms of the same instant.
JQ_EPOCH='
def to_epoch:
  capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})([.][0-9]+)?(?<z>Z|[+-][0-9]{2}:[0-9]{2})$") as $m
  | (($m.d + "Z") | fromdateiso8601) as $base
  | (if $m.z == "Z" then 0
     else ($m.z | capture("^(?<s>[+-])(?<h>[0-9]{2}):(?<mi>[0-9]{2})$")
           | (((.h|tonumber)*3600) + ((.mi|tonumber)*60)) * (if .s=="+" then 1 else -1 end))
     end) as $off
  | $base - $off;
def tagval($p): (.tags // []) | map(select(startswith($p))) | first // null | if . == null then null else .[($p|length):] end;
'

# ------------------------------------------------------------------- mailer
# Parses the SMTP credential out of the shoutrrr URL already stored in the
# config by the CONDITION_ANY_ERROR hooks.
urldecode() {
    # shellcheck disable=SC2059
    printf "$(printf '%s' "$1" | sed 's/%/\\x/g')"
}

SHOUTRRR_URL=$(jq -r '[.repos[]?.hooks[]? | select(.actionShoutrrr) | .actionShoutrrr.shoutrrrUrl] | first // empty' "$CFG")

send_mail() {
    _subject=$1
    _body=$2

    if [ -z "$SHOUTRRR_URL" ]; then
        log "ERROR: no shoutrrr hook found in $CFG; cannot send mail"
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
    _msg=$(mktemp /tmp/alert-check-msg.XXXXXX) || return 1
    {
        printf 'From: backrest <%s>\n' "$_from"
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

# clear_alert <key> - if the key was alerting, send one RESOLVED mail
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

is_skipped() {
    for _s in $SKIP_IDS; do [ "$1" = "$_s" ] && return 0; done
    return 1
}

# ------------------------------------------------------- gather per-repo data
STALE_SECS=$((STALE_HOURS * 3600))
SNAPDIR=$(mktemp -d /tmp/alert-check.XXXXXX) || exit 0
trap 'rm -rf "$SNAPDIR"' EXIT INT TERM

REPOS=$(jq -r '.repos[].id' "$CFG")

for REPO in $REPOS; do
    is_skipped "$REPO" && { log "skip repo $REPO"; continue; }
    (
        # Repo credentials come from backrest's own config; nothing on argv.
        eval "$(jq -r --arg r "$REPO" '.repos[]|select(.id==$r)|(.env[]?|"export \(.)")' "$CFG")"
        RESTIC_REPOSITORY=$(jq -r --arg r "$REPO" '.repos[]|select(.id==$r)|.uri' "$CFG"); export RESTIC_REPOSITORY
        RESTIC_PASSWORD=$(jq -r --arg r "$REPO" '.repos[]|select(.id==$r)|.password' "$CFG"); export RESTIC_PASSWORD
        "$RESTIC" snapshots --no-lock --json 2>"$SNAPDIR/$REPO.err" > "$SNAPDIR/$REPO.json"
    )
    if [ $? -ne 0 ] || [ ! -s "$SNAPDIR/$REPO.json" ]; then
        # Unreachable / broken: count it, do NOT claim staleness.
        _df="$STATE_DIR/degraded.$(printf '%s' "$REPO" | sha256sum | cut -c1-16)"
        _n=0; [ -f "$_df" ] && _n=$(cat "$_df" 2>/dev/null || echo 0)
        _n=$((_n + 1)); printf '%s' "$_n" > "$_df"
        log "repo $REPO unreachable (consecutive failures: $_n)"
        if [ "$_n" -ge "$DEGRADED_AFTER" ]; then
            alert "degraded:$REPO" "[backrest][$INSTANCE] CHECK DEGRADED: $REPO" \
"The staleness check has been unable to read repo '$REPO' $_n times in a row.

Instance : $INSTANCE
Repo     : $REPO
Time     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')

This is NOT a staleness alert - backups may be fine. It means monitoring is
blind for this repo, which must be fixed or the repo becomes unmonitored.

restic stderr:
$(head -c 1200 "$SNAPDIR/$REPO.err" 2>/dev/null)
"
        fi
        rm -f "$SNAPDIR/$REPO.json"
        continue
    fi
    rm -f "$STATE_DIR/degraded.$(printf '%s' "$REPO" | sha256sum | cut -c1-16)"
    clear_alert "degraded:$REPO" "monitoring can read repo $REPO again"
done

# ------------------------------------------------ Layer A: cross-host liveness
for REPO in $REPOS; do
    [ -f "$SNAPDIR/$REPO.json" ] || continue
    jq -r --arg self "$INSTANCE" --argjson now "$NOW" "$JQ_EPOCH"'
      [ .[] | {i: tagval("created-by:"), t: (.time|to_epoch)} ]
      | map(select(.i != null and .i != $self))
      | group_by(.i)[]
      | {i: .[0].i, newest: (map(.t)|max)}
      | "\(.i)\t\($now - .newest)"' "$SNAPDIR/$REPO.json" 2>/dev/null | while IFS="$(printf '\t')" read -r FI AGE; do
        [ -z "${FI:-}" ] && continue
        KEY="staleA:$REPO:$FI"
        if [ "$AGE" -gt "$STALE_SECS" ]; then
            alert "$KEY" "[backrest][$INSTANCE] STALE: host '$FI' has not backed up" \
"Layer A (cross-host liveness) - the OTHER host appears to have stopped.

Observed by : $INSTANCE
Silent host : $FI
Repo        : $REPO (shared)
Newest snapshot from '$FI' is $((AGE / 3600))h $(((AGE % 3600) / 60))m old
Threshold   : ${STALE_HOURS}h
Time        : $(date -u '+%Y-%m-%dT%H:%M:%SZ')

No snapshot from that instance has appeared in the shared repo within the
threshold. Its backrest may be stopped, wedged, or the host may be down.
Nothing on '$FI' can report this itself, which is the whole point of this check.
"
        else
            log "layerA ok: $FI in $REPO, age $((AGE / 3600))h"
            clear_alert "$KEY" "host '$FI' is writing snapshots again (repo $REPO)"
        fi
    done
done

# --------------------------------------------- Layer B: self, per configured plan
jq -r '.plans[] | select((.schedule.disabled // false) | not) | "\(.id)\t\(.repo)"' "$CFG" \
| while IFS="$(printf '\t')" read -r PLAN REPO; do
    is_skipped "$PLAN" && continue
    [ -f "$SNAPDIR/$REPO.json" ] || { log "layerB skip $PLAN (repo $REPO unreadable)"; continue; }
    AGE=$(jq -r --arg self "$INSTANCE" --arg plan "$PLAN" --argjson now "$NOW" "$JQ_EPOCH"'
      [ .[] | select(tagval("plan:") == $plan and tagval("created-by:") == $self) | (.time|to_epoch) ]
      | if length == 0 then -1 else ($now - max) end' "$SNAPDIR/$REPO.json" 2>/dev/null)
    KEY="staleB:$REPO:$PLAN"
    if [ "${AGE:--1}" = "-1" ]; then
        alert "$KEY" "[backrest][$INSTANCE] NO SNAPSHOTS: plan '$PLAN'" \
"Layer B (self check) - a configured plan has never produced a snapshot.

Instance : $INSTANCE
Plan     : $PLAN
Repo     : $REPO
Time     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')

The plan is enabled in the config but no snapshot tagged
plan:$PLAN,created-by:$INSTANCE exists in the repo.
"
    elif [ "$AGE" -gt "$STALE_SECS" ]; then
        alert "$KEY" "[backrest][$INSTANCE] STALE: plan '$PLAN'" \
"Layer B (self check) - a plan on THIS host has stopped producing snapshots.

Instance  : $INSTANCE
Plan      : $PLAN
Repo      : $REPO
Newest    : $((AGE / 3600))h $(((AGE % 3600) / 60))m old
Threshold : ${STALE_HOURS}h
Time      : $(date -u '+%Y-%m-%dT%H:%M:%SZ')

Other plans on this host are still running (this check runs from a backup
hook), so this is a single-plan failure rather than a dead host.
"
    else
        log "layerB ok: $PLAN in $REPO, age $((AGE / 3600))h"
        clear_alert "$KEY" "plan '$PLAN' is producing snapshots again"
    fi
done

# ------------------------------------------- Layer C: retention sanity ceiling
for REPO in $REPOS; do
    [ -f "$SNAPDIR/$REPO.json" ] || continue
    jq -r "$JQ_EPOCH"'
      [ .[] | {p: tagval("plan:"), i: tagval("created-by:")} ]
      | map(select(.p != null))
      | group_by([.p, .i])[]
      | "\(.[0].p)\t\(.[0].i // "-")\t\(length)"' "$SNAPDIR/$REPO.json" 2>/dev/null \
    | while IFS="$(printf '\t')" read -r PLAN INST N; do
        [ -z "${PLAN:-}" ] && continue
        KEY="countC:$REPO:$PLAN:$INST"
        if [ "$N" -gt "$MAX_SNAPSHOTS" ]; then
            alert "$KEY" "[backrest][$INSTANCE] RETENTION: $N snapshots for '$PLAN'" \
"Layer C (retention sanity) - snapshot count is above the ceiling.

Observed by : $INSTANCE
Repo        : $REPO
Plan        : $PLAN
Created by  : $INST
Snapshots   : $N   (ceiling ${MAX_SNAPSHOTS})
Time        : $(date -u '+%Y-%m-%dT%H:%M:%SZ')

Retention is not deleting anything even though forget may be reporting
success. This is the symptom that went unnoticed for 8 months and reached
7083 snapshots. Check for stale locks and check the forget task history.
"
        else
            log "layerC ok: $PLAN/$INST in $REPO, n=$N"
            clear_alert "$KEY" "snapshot count for '$PLAN' is back under the ceiling"
        fi
    done
done

log "done (instance=$INSTANCE threshold=${STALE_HOURS}h ceiling=${MAX_SNAPSHOTS})"
exit 0
