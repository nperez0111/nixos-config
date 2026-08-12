FROM restic/restic:0.19.1

# sqlite  - online .backup API for consistent snapshots of live WAL databases
# curl/jq - result reporting to OpenObserve
# tzdata  - so TZ=Europe/Amsterdam makes cron fire at local 04:00
RUN apk add --no-cache sqlite curl jq tzdata

COPY server/backup/run-backup.sh /usr/local/bin/run-backup.sh
COPY server/backup/excludes /etc/restic-excludes
COPY server/backup/crontab /etc/crontabs/root

RUN chmod +x /usr/local/bin/run-backup.sh

# The base image sets ENTRYPOINT ["/usr/bin/restic"]; clear it so CMD is the process.
ENTRYPOINT []

# -f foreground (so docker sees the process), -d 8 log to stderr (so docker logs sees jobs)
CMD ["crond", "-f", "-d", "8", "-c", "/etc/crontabs"]
