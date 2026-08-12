# Monitoring the bastion offsite backup

The backup container reports the outcome of **every** run to OpenObserve. Until
an alert is configured on top of that data, nothing is watching it — the events
just accumulate. This document is the click-path for closing that gap.

---

## 1. What gets sent

After each run — success *or* failure — `run-backup.sh` POSTs a single JSON
record to:

```
http://openobserve:5080/api/default/backup/_json
```

That creates/appends to the **`backup`** stream in the **`default`** org. The
stream is created automatically on first ingest; there is nothing to set up.

Record shape:

| Field | Type | Notes |
|---|---|---|
| `event` | string | always `restic_backup` |
| `status` | string | `success` or `failure` |
| `mode` | string | `backup`, `prune`, `check`, `init` |
| `reason` | string | failure message; empty on success |
| `host` | string | `bastion` |
| `started_at` | string | ISO-8601 UTC |
| `duration_seconds` | number | wall clock |
| `databases_snapshotted` | number | expect ~163 |
| `snapshot_id` | string | restic snapshot id, null unless `mode=backup` |
| `files_new` | number | |
| `files_changed` | number | |
| `total_files_processed` | number | |
| `total_bytes_processed` | number | |
| `data_added` | number | bytes actually uploaded — the interesting one |

Verify data is arriving (OpenObserve UI → **Logs** → stream `backup`):

```sql
SELECT * FROM backup ORDER BY _timestamp DESC LIMIT 10
```

---

## 2. The alert that actually matters

There are two failure modes, and they are not equally dangerous:

1. **A run fails loudly** — bad credentials, B2 unreachable, `quick_check`
   fails. This emits `status: "failure"` and is easy to alert on.
2. **Nothing runs at all** — the container is stopped, crashed, `crond` died,
   the stack was removed, the host is down. This emits **nothing**. From the
   outside it is indistinguishable from a healthy system.

Case 2 is the one that quietly eats backups for six months. The only alert that
catches it is a **dead-man's switch**: fire when there has been *no* success in
longer than expected. Configure that one first. If you only ever configure one
alert, make it that one.

---

## 3. Set up a notification destination

Alerts need somewhere to go. In OpenObserve:

**Management → Alert Destinations** (and **Templates**).

1. Create a **Template** — the body of the message. A minimal webhook template:

   ```json
   {
     "text": "[{alert_name}] backup alert on {stream_name} — {alert_type}"
   }
   ```

   Placeholders in `{...}` are substituted by OpenObserve; row fields from the
   query are available as `{field_name}`.

2. Create a **Destination** — name it, paste the webhook URL (ntfy, Discord,
   Slack, whatever you use), method `POST`, and select the template above.

   For email, configure SMTP on the OpenObserve instance first, then choose an
   email destination instead.

---

## 4. Alert A — dead-man's switch (required)

**Alerts → Add Alert**

| Field | Value |
|---|---|
| Name | `backup-missing` |
| Stream type | `logs` |
| Stream | `backup` |
| Alert type | **Scheduled** |
| Query type | **SQL** |
| Period | `36` minutes... no — see note below |
| Frequency | every `60` minutes |
| Destination | the one from §3 |
| Silence | `720` minutes (12h) so it nags rather than spams |

Query:

```sql
SELECT count(*) AS success_count
FROM backup
WHERE status = 'success' AND mode = 'backup'
```

Trigger condition:

```
success_count  <  1
```

**Period: 2160 minutes (36 hours).** Backups run daily at 04:00 Europe/Amsterdam,
so 36h allows one run to be missed or delayed without paging, while still
catching a genuinely dead backup within a day and a half.

> **Important gotcha.** Some OpenObserve versions do not evaluate a scheduled
> alert at all if the query returns *zero rows* — which is exactly the situation
> a dead-man's switch needs to detect. Using `count(*)` avoids this: an
> aggregate always returns one row, containing `0`. Do **not** rewrite this as
> `SELECT * FROM backup WHERE ...` with a "no results" condition; it will
> silently never fire.
>
> Verify the alert works before trusting it — see §7.

---

## 5. Alert B — an explicit failure was reported

| Field | Value |
|---|---|
| Name | `backup-failed` |
| Stream | `backup` |
| Alert type | **Real-time** |
| Condition | `status` `=` `failure` |
| Destination | the one from §3 |
| Silence | `240` minutes |

Real-time alerts evaluate on ingest, so this pages within seconds of a failed
run. The `reason` field carries the message; include `{reason}` and `{mode}` in
the template to get it in the notification.

---

## 6. Alert C — silent shrinkage (optional, worth it)

Catches the case where the job "succeeds" but is backing up nothing useful —
e.g. a volume stopped being mounted, or discovery broke.

| Field | Value |
|---|---|
| Name | `backup-too-few-databases` |
| Alert type | **Scheduled**, SQL |
| Period | `2160` minutes |
| Frequency | `1440` minutes |

```sql
SELECT min(databases_snapshotted) AS min_dbs
FROM backup
WHERE status = 'success' AND mode = 'backup'
```

Trigger: `min_dbs < 100`.

Expected count is ~163 and grows with every PDS signup, so a floor of 100 is
generous. `run-backup.sh` already hard-fails at zero, so this is specifically
about catching a *partial* loss.

---

## 7. Test the alerts before trusting them

An untested alert is a comfort blanket, not monitoring.

**Alert B (failure):** run the script with deliberately broken credentials.

```sh
ssh bastion
docker exec -e RESTIC_PASSWORD=wrong backup /usr/local/bin/run-backup.sh backup
```

It should fail fast, emit `status: failure`, and notify.

**Alert A (dead-man's switch):** temporarily narrow the period to a few minutes
and confirm it fires, then set it back to 2160. Alternatively point it at a
stream name that does not exist — it should still evaluate and fire, which is
the behaviour being verified.

Re-test whenever OpenObserve is upgraded; alert semantics have changed between
versions.

---

## 8. Useful ad-hoc queries

Last 30 runs:

```sql
SELECT started_at, mode, status, duration_seconds,
       databases_snapshotted, data_added
FROM backup
ORDER BY _timestamp DESC
LIMIT 30
```

Upload volume trend — a sudden jump usually means dedup broke (e.g. someone
switched `.backup` for `VACUUM INTO`):

```sql
SELECT started_at, data_added / 1048576 AS mib_added
FROM backup
WHERE mode = 'backup' AND status = 'success'
ORDER BY _timestamp DESC
LIMIT 30
```

Runtime creep:

```sql
SELECT started_at, duration_seconds
FROM backup
WHERE mode = 'backup'
ORDER BY _timestamp DESC
LIMIT 30
```

---

## 9. Manual health check

When you want to look with your own eyes rather than trust the pipeline:

```sh
ssh bastion
docker logs backup --tail 100          # crond + last run output
docker exec backup restic snapshots    # what is actually in B2
```

A healthy `restic snapshots` shows one snapshot per day, host `bastion`, tag
`scheduled`, going back through the retention window (14 daily, 8 weekly,
12 monthly).
