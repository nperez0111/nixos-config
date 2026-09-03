#!/bin/sh
# alert-error.sh - damped failure notifications for backrest tasks.
#
# WHY THIS EXISTS
# ---------------
# backrest's CONDITION_ANY_ERROR hook fires on every failed task and has no
# memory: a one-off Hetzner 503 at 01:19, a lock collision with the other host
# during forget, and a hook that has been broken for a week all produce the
# same email, once per run. The result was alert fatigue, and the mail that
# mattered (bastion silently not backing up for six days) went unread.
#
# This script replaces the direct shoutrrr hook. It is called twice per task
# kind from repo-level hooks:
#
#   on CONDITION_ANY_ERROR:
#     printf '%s' {{ .ShellEscape .Error }} | alert-error.sh fail PLAN REPO TASK
#   on CONDITION_{SNAPSHOT,FORGET,PRUNE,CHECK}_SUCCESS:
#     alert-error.sh ok PLAN REPO TASK
#
# and keeps one consecutive-failure counter per (repo, plan, task kind), where
# task kind is the first word of backrest's task name: "backup", "forget",
# "prune", "check".
#
#   fail  increments the counter. Mail is sent only once the counter reaches
#         BACKREST_ERROR_THRESHOLD (default 2) - i.e. the SAME task failed on
#         consecutive runs - and then at most once per BACKREST_ALERT_REPEAT_HOURS
#         (default 24) while it keeps failing. The first failure is logged in
#         the hook output and nothing else.
#   ok    resets the counter. If a FAILURE mail had been sent for the key, one
#         RESOLVED mail follows so the thread closes itself.
#
# Consequences worth knowing:
#   * a daily plan that fails once and succeeds the next night never mails.
#   * a daily plan that is genuinely broken mails on night 2 (~24h after the
#     first failure), then once a day. alert-check.sh independently raises
#     STALE at 36h, so a broken plan produces two distinct signals, not a flood.
#   * the error text of the LATEST failure is in the mail body, so the
#     "what is wrong" information the shoutrrr hook used to carry is kept.
#
# Exit status is always 0: this runs as a hook with the default ON_ERROR_IGNORE,
# and a non-zero exit would add a spurious hook failure to the operation.

set -u

LOG_TAG=alert-error
# shellcheck source=alert-lib.sh
. "$(dirname "$0")/alert-lib.sh"

THRESHOLD=${BACKREST_ERROR_THRESHOLD:-2}

MODE=${1:-}; PLAN=${2:-_system_}; REPO=${3:-}; TASK=${4:-}
[ -z "$PLAN" ] && PLAN=_system_
KIND=${TASK%% *}
[ -z "$KIND" ] && KIND=unknown

KEY="err:$REPO:$PLAN:$KIND"
COUNTFILE="$STATE_DIR/count.$(printf '%s' "$KEY" | sha256sum | cut -c1-32)"

case "$MODE" in
fail)
    ERR=$(cat)
    N=0; FIRST=$NOW
    if [ -f "$COUNTFILE" ]; then
        N=$(cut -d' ' -f1 < "$COUNTFILE" 2>/dev/null); FIRST=$(cut -d' ' -f2 < "$COUNTFILE" 2>/dev/null)
        case "$N" in ''|*[!0-9]*) N=0 ;; esac
        case "$FIRST" in ''|*[!0-9]*) FIRST=$NOW ;; esac
    fi
    N=$((N + 1))
    printf '%s %s\n' "$N" "$FIRST" > "$COUNTFILE"
    log "failure $N of $KIND for plan '$PLAN' (repo $REPO)"
    if [ "$N" -lt "$THRESHOLD" ]; then
        log "suppressed: below threshold $THRESHOLD; mail only if the next run fails too"
        printf '%s\n' "$ERR" | head -c 4000 | sed 's/^/[error] /'
        exit 0
    fi
    AGE=$((NOW - FIRST))
    alert "$KEY" "[backrest][$INSTANCE] FAILURE: $KIND for plan '$PLAN' ($N in a row)" \
"backrest FAILURE - the same task has failed on $N consecutive runs.

Instance : $INSTANCE
Repo     : $REPO
Plan     : $PLAN
Task     : $TASK
Failing since : $(date -u -d "@$FIRST" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "$FIRST") ($((AGE / 3600))h ago)
Time     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')

Latest error:
$(printf '%s' "$ERR" | head -c 6000)

--
This mail repeats at most every ${REPEAT_HOURS}h while the task keeps failing
and is followed by a RESOLVED mail on the next success. A single failure that
clears itself on the next run is deliberately not mailed.
If Task is forget/prune, retention has stopped working even though backups
may still be succeeding.
"
    ;;
ok)
    if [ -f "$COUNTFILE" ]; then
        N=$(cut -d' ' -f1 < "$COUNTFILE" 2>/dev/null)
        rm -f "$COUNTFILE"
        log "$KIND for plan '$PLAN' succeeded after ${N:-?} failure(s); counter reset"
        clear_alert "$KEY" "$KIND for plan '$PLAN' (repo $REPO) is succeeding again"
    else
        log "$KIND for plan '$PLAN' ok"
    fi
    ;;
*)
    log "usage: alert-error.sh fail|ok PLAN REPO TASK   (error text on stdin for fail)"
    ;;
esac
exit 0
