# Restoring from the bastion offsite backup

The `backup` stack on **bastion** ships Docker volume contents to Backblaze B2
with [restic](https://restic.net/). This document is the runbook for getting
data back out. It has been exercised at least once against the live repository —
if you change the backup script, exercise it again.

---

## 1. What is actually in a snapshot

Each snapshot contains two top-level trees:

| Path in snapshot | Contents |
|---|---|
| `/staging/<volume>/<relative path>` | **Consistent SQLite database snapshots** taken with SQLite's online backup API. These are what you restore a database from. |
| `/src/<volume>/<relative path>` | **Everything else** — epubs, covers, PDS blocks, uploads, keys. The live `*.sqlite` / `*.db` files and their `-wal` / `-shm` siblings are deliberately excluded here. |

A volume is therefore reconstituted by **merging the two trees**: files from
`/src/<volume>` plus databases from `/staging/<volume>`, both laid down at the
same relative paths.

> The live `db.sqlite`, `db.sqlite-wal` and `db.sqlite-shm` are *not* in the
> snapshot. That is intentional — a raw copy of a WAL database taken while a
> writer is running is a torn image. The `/staging` copy is the good one, and it
> is a single self-contained file with no `-wal` or `-shm` beside it. SQLite will
> recreate those on first open.

Volumes currently covered:

- `bookhive_data` — `db.sqlite`, `kv.sqlite`, `library/`, `exports/`
- `bookhive_social_data` — `account.sqlite`, `did_cache.sqlite`, `sequencer.sqlite`, ~158 per-actor `actors/**/store.sqlite`, `blocks/`
- `pocket-id_data` — `pocket-id.db`, `keys/`, `uploads/`
- `catnip_data` — `registry.db`
- `kosync_data` — `koreader-sync.db`
- `wedding_wedding_db` — `db.sqlite`

Excluded by design: `bookhive_data/db.sqlite.pre197` (a stale 1.5 GB one-off),
`bookhive_social_data/temp/`, `catnip_data/tmp/`.

---

## 2. Getting a restic shell

Everything below runs on **bastion**, in a throwaway container that has the
credentials and the repository cache. Nothing here mounts a source volume, so it
cannot damage live data.

```sh
ssh bastion

docker run --rm -it \
  --network backbone \
  --env-file <(docker inspect backup \
    --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -E '^(RESTIC_|AWS_)') \
  -v restic_cache:/cache \
  -v /var/tmp/restore:/restore \
  ghcr.io/nperez0111/nixos-config-backup:main \
  sh
```

If the `backup` container is gone, set the four variables by hand instead —
they are on the `backup` stack in Portainer (bastion, endpoint `2761600`):

```sh
export RESTIC_REPOSITORY=s3:s3.us-west-000.backblazeb2.com/general-backup-nickthesick-com/bastion
export RESTIC_PASSWORD=...          # password manager
export AWS_ACCESS_KEY_ID=...        # B2 keyID
export AWS_SECRET_ACCESS_KEY=...    # B2 applicationKey
export RESTIC_CACHE_DIR=/cache
```

Sanity check:

```sh
restic snapshots
```

---

## 3. Restoring

### Everything, latest snapshot

```sh
restic restore latest --target /restore
```

Gives you `/restore/staging/...` and `/restore/src/...` — on the host that is
`/var/tmp/restore/`.

### A single volume

```sh
restic restore latest --target /restore \
  --include /staging/bookhive_data \
  --include /src/bookhive_data
```

### A single file, without unpacking everything

```sh
restic dump latest /staging/bookhive_data/db.sqlite > /restore/db.sqlite
```

`restic dump` streams straight out of the repository, which is the fastest way
to pull one 1.7 GB database.

### A point in time

```sh
restic snapshots                       # find the id / date you want
restic restore <snapshot-id> --target /restore
```

---

## 4. Verify before you trust it

Never put a restored database into service without checking it.

```sh
sqlite3 /restore/staging/bookhive_data/db.sqlite 'PRAGMA integrity_check;'
# must print exactly: ok

sqlite3 /restore/staging/bookhive_data/db.sqlite \
  'SELECT count(*) FROM sqlite_master;'
```

For the file trees, spot-check a few real objects:

```sh
find /restore/src/bookhive_data/library -name '*.epub' | head -3
# epubs are zip archives; the first two bytes must be PK
head -c 2 "$(find /restore/src/bookhive_data/library -name '*.epub' | head -1)"

find /restore/src/bookhive_social_data/blocks -type f | wc -l
```

---

## 5. Putting data back into a live volume

**Stop the consuming container first.** Restoring underneath a running SQLite
writer will corrupt what you just restored.

```sh
docker stop bookhive
```

Then merge both trees into the volume. Using a helper container avoids touching
`/var/lib/docker/volumes` by hand:

```sh
docker run --rm \
  -v bookhive_data:/target \
  -v /var/tmp/restore:/restore:ro \
  alpine sh -c '
    cp -a /restore/src/bookhive_data/.     /target/ &&
    cp -a /restore/staging/bookhive_data/. /target/
  '
```

Order matters: `/staging` is copied **second** so the consistent database
snapshots win over anything of the same name in `/src`.

Fix ownership to match what the service expects (see the table below), then
start it:

```sh
docker run --rm -v bookhive_data:/target alpine chown -R 1000:1000 /target
docker start bookhive
docker logs -f bookhive
```

| Volume | Owner |
|---|---|
| `bookhive_data` | `1000:1000` |
| `pocket-id_data` | `1000:1000` |
| `kosync_data` | `1000:1000` |
| `bookhive_social_data` | `root:root` |
| `catnip_data` | `root:root` |
| `wedding_wedding_db` | `root:root` |

### Restoring into a fresh volume instead

Safer when you are not certain the backup is good — keeps the original intact:

```sh
docker volume create bookhive_data_restored
# ...copy into bookhive_data_restored as above...
# then point the stack at it in Portainer, or swap the names once verified
```

---

## 6. Disaster recovery: bastion is gone

The repository is entirely self-contained in B2. You need exactly two things:

1. `RESTIC_PASSWORD` — **there is no reset path.** If this is lost the data is
   cryptographically unrecoverable. It lives in the password manager.
2. B2 credentials — regenerable at any time from the Backblaze console.

From any machine with restic installed:

```sh
export RESTIC_REPOSITORY=s3:s3.us-west-000.backblazeb2.com/general-backup-nickthesick-com/bastion
export RESTIC_PASSWORD=...
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...

restic snapshots
restic restore latest --target ./restore
```

**What is *not* in this backup:** application secrets. `PRIVATE_KEY_JWK`,
`COOKIE_SECRET`, `IMGPROXY_KEY` and friends live only as Portainer stack
environment variables, which live in Portainer's database on **macmini**. A
full rebuild of bastion needs those too, and they are a separate problem.

---

## 7. Troubleshooting

**`Fatal: unable to open config file` / `repository does not exist`**
Wrong `RESTIC_REPOSITORY`, wrong credentials, or the key lost access to the
bucket. Confirm with `restic cat config`.

**`wrong password or no key found`**
`RESTIC_PASSWORD` is wrong. There is no recovery. Check the password manager.

**`prune` fails with an access-denied error**
The B2 application key lacks **delete** permission. `init`, `backup` and
`restore` all work without it; only `prune` and `forget` need it. Regenerate the
key with delete rights and update the stack env.

**Restore is slow**
Expected. B2 downloads are metered and restic reassembles from many small packs.
Use `restic dump` for a single file, or `--include` to narrow the restore.

**`repository is already locked`**
A previous run died mid-operation. Confirm nothing is actually running, then:

```sh
restic unlock
```
