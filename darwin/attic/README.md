# attic — iCloud Photos → Backblaze B2

Nightly backup of the Photos library. Deployed 2026-08-28, currently on
`1.0.0-beta.25`.

| | |
|---|---|
| Package | `pkgs.attic-photos`, pinned in [`../../overlays/attic/default.nix`](../../overlays/attic/default.nix) |
| Agents | `org.nixos.attic-{backup,verify,check,prime}`, defined in [`../default.nix`](../default.nix) |
| Config | `~/.attic/config.json` (not in git — written by `attic init`) |
| Credentials | macOS login keychain, services `attic-s3-access-key` / `attic-s3-secret-key`, account `attic` |
| Bucket | `attic-backup-nickthesick-com` at `s3.us-west-000.backblazeb2.com`, path-style |
| Logs | `~/Library/Logs/attic/{backup,verify,check,prime}.log` |

Operational runbook (what to do when it alerts) is in `~/AGENTS.md` on the
macmini, under "iCloud Photos Backup". This file is the **upgrade** procedure.

## The two rules

**1. attic must be launchd's direct `ProgramArguments`. Never wrap it in a
shell script.**

TCC attributes a Photos request to the process launchd started, not to the one
making the request. Wrapping attic to capture its exit status makes the
nix-store bash the responsible process, and tccd then asks to grant Photos
access to *bash*:

```
AUTHREQ_ATTRIBUTION: requesting={identifier=attic}, responsible={identifier=bash}
AUTHREQ_PROMPTING:   subject=Sub:{/nix/store/...-bash-5.3p9/bin/bash}
```

The backup hangs forever on that prompt. Approving it is worse than the hang —
it grants the whole Photos library to a bash shared by every script on the
system. This was hit and reverted on 2026-08-28; don't reintroduce it. Outcome
is read *after the fact* by `attic-notify`, from launchd's own `last exit code`.

**2. Every version bump breaks both permissions and needs a re-prime.**

The release binary is ad-hoc, linker-signed. Its keychain ACL is keyed to the
content hash and its Photos TCC grant to the store path — a new version changes
both. Symptoms: `Failed to read keychain item`, or a run that reports
`0 uploaded, 0 failed` with assets pending.

## Storage behaviour

The library is on "Optimize Mac Storage", so originals live in iCloud, not on
disk. attic pulls each one through PhotoKit, uploads it, and deletes its own
copy — but macOS *retains* what it downloaded and only evicts lazily under disk
pressure. So a run has two footprints:

| | Behaviour |
|---|---|
| `~/.attic/staging` | Self-clearing rolling buffer. Observed 290–500 MB mid-run; aborted runs leave files behind deliberately, for reuse on the next run. |
| `Photos Library.photoslibrary` | **Grows.** Measured over the first 249 assets: originals 1.4 GB → 4.2 GB while attic uploaded 3.02 GB — a near-exact match, i.e. the growth is attic's downloads being retained. |

Sizing, measured 2026-08-28 from the first 249 assets (187 photos averaging
2.9 MB, 62 videos averaging 40 MB) weighted to the library's real ~11% video
share: **≈67 GB** for all 9,573 assets. Free space at deploy was 102 GB.

**Decided 2026-08-28: no free-space guard.** Evicting under pressure is exactly
what Optimize Mac Storage is for, and 67 GB fits the available space. This is a
deliberate choice, not an oversight — revisit it if the mini gets tighter on
disk, since Immich (345 GB), Seafile and Docker share the volume. A guard would
naturally live in `attic-notify check`, which already runs daily and can mail.

## Checking it is working

```sh
attic status          # progress %, backed up vs pending, manifest entries
attic-notify check    # logs "healthy: last run Nh ago, exit code 0"; mails only on trouble
tail -f ~/Library/Logs/attic/backup.log
```

`attic verify` (weekly, Sunday 07:00) is the real integrity check — it confirms
every manifest entry still exists in S3, rather than trusting the manifest.

## Upgrading

1. **Check whether the workaround is still needed.** beta.25 ships neither the
   `--on-failure` / `--on-success` hooks nor the `--json` streams that
   upstream's `docs/unattended-backups.md` documents — those were on unreleased
   `main`. Confirm against the binary, not the docs:

   ```sh
   attic backup --help    # look for --on-failure / --on-success / --json
   attic status --help    # look for --json
   ```

   If they have landed, see "Simplifying" below.

2. **Bump the pin** in `../../overlays/attic/default.nix`:

   ```sh
   V=1.0.0-beta.26   # new tag, without the leading v
   URL=https://github.com/tijs/attic/releases/download/v$V/attic-$V-aarch64-apple-darwin.tar.gz
   nix-prefetch-url "$URL"          # NOT --unpack; fetchurl hashes the tarball
   curl -sL https://github.com/tijs/attic/releases/download/v$V/checksums.txt
   ```

   Cross-check the hash against `checksums.txt` before committing.

3. **Build and switch.** `./bin/build`. Note this reloads the agents, so it
   SIGTERMs any backup in flight — harmless (attic is idempotent and resumes
   from the manifest and retry queue), but it shows up as exit 143 and
   `attic-check` will mail BACKUP FAILED for it.

4. **Re-prime, at a GUI session** (Screen Sharing is enabled on the mini):

   ```sh
   launchctl kickstart -k gui/$(id -u)/org.nixos.attic-prime
   ```

   Answer **Always Allow** on both keychain prompts — not "Allow", only
   "Always Allow" writes the ACL entry that lets background launchd runs skip
   it — and **Allow** on the Photos prompt.

   Before clicking anything, confirm the prompt is attributed to attic and not
   to a shell:

   ```sh
   sudo log show --last 5m --predicate 'subsystem == "com.apple.TCC"' --style compact \
     | grep AUTHREQ_PROMPTING
   ```

   The `subject=` must be the attic store path. If it names bash, something has
   reintroduced a wrapper — fix that instead of approving.

5. **Verify:**

   ```sh
   launchctl kickstart -k gui/$(id -u)/org.nixos.attic-prime
   tail ~/Library/Logs/attic/prime.log     # library + S3 stats, no errors
   attic-notify check                      # should log "healthy", send nothing
   ```

   Then let one real backup run, or kickstart `org.nixos.attic-backup` and watch
   `backup.log` for `✓` lines.

## Simplifying, once hooks are released

When `--on-failure` / `--on-success` exist, the outcome no longer has to be
inferred after the fact. Keep attic as launchd's direct program — rule 1 still
applies, and it still holds, because hooks run as attic's *children*, which
does not change TCC attribution.

- add `--on-failure "attic-notify hook" --on-success "attic-notify hook"` to the
  `attic-backup` agent
- give `attic-notify` a `hook` mode reading `ATTIC_RESULT`, plus
  `ATTIC_UPLOADED` / `ATTIC_FAILED` / `ATTIC_SKIPPED` / `ATTIC_TOTAL_BYTES`
  (only set when the run completed; absent on an early abort)
- keep the staleness half of `check` regardless. A hook only fires when a run
  happens, so it is structurally blind to the agent not firing at all — the
  same gap `server/backrest/alert-check.sh` exists to close.

`attic status --json` would also let the check read `.s3.lastBackupAt` instead
of the log's mtime, which is a truer "last successful backup" signal.

## Rolling back

Revert the version and hash, `./bin/build`, then re-prime (step 4) — downgrading
changes the binary too, so the permissions break in the same way.

One-way door to watch for: `1.0.0-beta.8` migrated the manifest to cloud
identifiers and older binaries cannot read a v2 manifest. Upstream keeps the
pre-migration copy as `manifest.v1.json` on S3. Do not downgrade across a
manifest migration without restoring that first.
