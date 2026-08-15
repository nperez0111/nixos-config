# AGENTS.md - nix-darwin Configuration

## Project Overview

This is a declarative nix-darwin configuration that manages:
- Mac Mini (darwin/aarch64-darwin)
- Homebrew packages
- Home Manager configurations
- Custom nix overlays

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `flake.nix` | Flake defining darwinConfigurations |
| `darwin/` | MacOS/nix-darwin configuration |
| `common/` | Shared configurations (home-manager) |
| `overlays/` | Custom nixpkgs overlays for DMG apps |
| `bin/` | Build scripts |
| `secrets/` | Age-encrypted secrets (agenix) |
| `server/` | Server tooling: caddy image + `caddy-manage`, backrest backup image |
| `configs/` | Game configs (dolphin, ryujinx, etc.) |

## Finding Things

### Darwin Configuration (Mac Mini)
- `darwin/default.nix` - Main system config, imports common, home-manager, skhd
- `darwin/home-manager.nix` - User-level config, homebrew, dock
- `darwin/brews.nix` - Homebrew CLI packages (opencode, mcfly, direnv, etc.)
- `darwin/casks.nix` - Homebrew GUI apps (brave, orion, orbstack, raycast, etc.)
- `darwin/packages.nix` - Nix packages for darwin
- `darwin/dock/default.nix` - Declarative dock configuration

### Shared/Common
- `common/default.nix` - nixpkgs config (allowUnfree, allowBroken)
- `common/home-manager.nix` - Shared shell, git, vscode, tmux, gh configs
- `common/packages.nix` - Shared packages (bat, fzf, gh, ripgrep, etc.)
- `common/files.nix` - Shared dotfiles (git template, gh hosts)
- `common/cachix/default.nix` - Cachix configuration

### Build Scripts
- `bin/build` - Builds darwin configuration
- `bin/darwin-build` - Builds darwin configuration
- `bin/update` - Updates flake inputs

### Secrets (agenix)
- `secrets/secrets.nix` - Secret definitions
- `secrets/github` - GitHub token (age-encrypted)

### Server / Docker images
Note `.gitignore` has `server/*`, so new files under `server/` are invisible to
git unless the directory is un-ignored (`!server/backrest/`) or force-added.
`server/caddy/Dockerfile` is tracked despite not being un-ignored, because
already-tracked files are unaffected by `.gitignore`.

- `server/caddy/Dockerfile` - Caddy + cloudflare DNS plugin
- `server/caddy-manage` - Caddyfile read/write/deploy tool (`caddy-manage help`)
- `server/backrest/` - the backup system for **both** hosts (macmini + bastion)
  - `Dockerfile` - backrest + restic + sqlite3 + pg_dump/mariadb-dump + jq/curl
  - `dump-databases.sh` - `SNAPSHOT_START` hook; writes consistent DB dumps to
    `/staging`. Driven by `SQLITE_SCAN_ROOTS`, `SQLITE_DB_ROOTS`, `PG_*`,
    `MYSQL_*`, `PORTAINER_*` env vars set on the Portainer stack.
  - `alert-check.sh` - `SNAPSHOT_END` hook; staleness / retention monitoring.
  - **Operational runbook (restore procedure, alerting, gotchas) lives in
    `~/AGENTS.md` under "Offsite Backups", not here.**
- `.github/workflows/docker-build.yml` - matrix build of both images to GHCR as
  `ghcr.io/nperez0111/nixos-config-{caddy,backrest}:main`. Adding an image means
  creating `server/<name>/Dockerfile`, adding `<name>` to `matrix.image`, and
  adding `!server/<name>/` to `.gitignore`.

> **Retired 2026-08-15:** `server/backup/` (the bastion-only restic + busybox
> `crond` image, Portainer stack 88, `ghcr.io/nperez0111/nixos-config-backup`)
> was deleted after bastion was migrated to backrest and a restore drill passed
> on both hosts. Do not resurrect its `cap_add: [DAC_OVERRIDE, SETGID]` workaround
> — that was a busybox-crond requirement; backrest uses an in-process Go
> scheduler and needs no added capabilities.

## Important Users
- Darwin: `nickthesick`

## Build Commands
```sh
./bin/build           # Build darwin config
./bin/darwin-build   # Build darwin config
nix flake update      # Update flake inputs
```

## Agent Workflow

- After making configuration changes, run `./bin/build` to apply them. Building is part of the task -- do not leave it for the user unless there is a reason to defer.
- If the build fails, fix the issue and rebuild.

## Notes
- User identity: Nick the Sick <nick@nickthesick.com>
- GPG key: `0AD7F8215DF25741E7DC79F3420226D226E30AF2`
- SSH keys: stored in `secrets/ssh_pub`
- Uses spaceship-prompt for zsh
- Uses skhd for hotkeys on darwin
