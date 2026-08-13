FROM garethgeorge/backrest:v1.14.1

# Database client tooling for the pre-snapshot hook. backrest runs hooks INSIDE
# this container, so everything dump-databases.sh calls has to live here.
#
#   sqlite              /usr/bin/sqlite3, the online .backup API
#   postgresql17-client pg_dump/pg_restore. Must be >= the 14 on the server;
#                       a newer client dumping an older server is supported,
#                       the reverse is not.
#   mariadb-client      /usr/bin/mariadb-dump
#   jq                  building JSON request bodies safely
#
# curl is already in the base image at /usr/bin/curl, so it is not installed.
RUN apk add --no-cache sqlite postgresql17-client mariadb-client jq

COPY server/backrest/dump-databases.sh /usr/local/bin/dump-databases.sh

RUN chmod +x /usr/local/bin/dump-databases.sh

# No ENTRYPOINT/CMD override: backrest must still start exactly as it does in
# the base image. This layer only adds tools next to it.
