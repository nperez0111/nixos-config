FROM garethgeorge/backrest:v1.14.1

# Database client tooling for the pre-snapshot hook. backrest runs hooks INSIDE
# this container, so everything dump-databases.sh calls has to live here.
#
#   sqlite              /usr/bin/sqlite3, the online .backup API
#   postgresql18-client pg_dump/pg_restore. Must be >= the newest server it is
#                       pointed at; a newer client dumping an older server is
#                       supported, the reverse is not. pg_dump aborts outright
#                       with "server version mismatch" against a newer major.
#
#                       This image serves two hosts with different servers:
#                         bastion  docs_postgres     PostgreSQL 16 (since
#                                                    2026-09-03; bookorbit-db,
#                                                    PG 18.6, was retired)
#                         macmini  immich_postgres   PostgreSQL 14.19
#                       Keep the client at 18.x anyway: it was 17 until the
#                       bookorbit floor moved to 18.6 and failed every bastion
#                       backup (the hook is ON_ERROR_FATAL, so one refused
#                       dump aborted the whole snapshot). A newer client is
#                       always safe; an older one is not.
#   mariadb-client      /usr/bin/mariadb-dump
#   jq                  building JSON request bodies safely
#
# curl is already in the base image at /usr/bin/curl, so it is not installed.
RUN apk add --no-cache sqlite postgresql18-client mariadb-client jq

COPY server/backrest/dump-databases.sh /usr/local/bin/dump-databases.sh

# Active staleness / retention monitoring. backrest's hook Condition enum has no
# "a backup did not run" event and structurally cannot -- hooks only fire from
# inside a running task. The repo-level CONDITION_ANY_ERROR hooks cover every
# failure; this script covers absence, which is how the old bastion crond died
# silently. It needs only curl/restic/jq, all already present above.
COPY server/backrest/alert-check.sh /usr/local/bin/alert-check.sh

# Damped failure mail (replaces the direct CONDITION_ANY_ERROR shoutrrr hooks,
# 2026-09-03): mails only when the same task fails on consecutive runs, at most
# once per 24h, and sends RESOLVED on the next success. alert-lib.sh is the
# mailer + dedupe state shared by both alert scripts; it reads the SMTP
# credential from BACKREST_SMTP_URL in the stack Env.
COPY server/backrest/alert-lib.sh /usr/local/bin/alert-lib.sh
COPY server/backrest/alert-error.sh /usr/local/bin/alert-error.sh

RUN chmod +x /usr/local/bin/dump-databases.sh /usr/local/bin/alert-check.sh \
    /usr/local/bin/alert-lib.sh /usr/local/bin/alert-error.sh

# No ENTRYPOINT/CMD override: backrest must still start exactly as it does in
# the base image. This layer only adds tools next to it.
