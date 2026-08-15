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
#                         bastion  bookorbit-db      PostgreSQL 18.6
#                         macmini  immich_postgres   PostgreSQL 14.19
#                       so the client has to be 18.x. It was 17 until that
#                       floor moved to 18.6 and failed every bastion backup
#                       (the hook is ON_ERROR_FATAL, so one refused dump
#                       aborted the whole snapshot). 18.4 is verified against
#                       both servers above.
#   mariadb-client      /usr/bin/mariadb-dump
#   jq                  building JSON request bodies safely
#
# curl is already in the base image at /usr/bin/curl, so it is not installed.
RUN apk add --no-cache sqlite postgresql18-client mariadb-client jq

COPY server/backrest/dump-databases.sh /usr/local/bin/dump-databases.sh

RUN chmod +x /usr/local/bin/dump-databases.sh

# No ENTRYPOINT/CMD override: backrest must still start exactly as it does in
# the base image. This layer only adds tools next to it.
