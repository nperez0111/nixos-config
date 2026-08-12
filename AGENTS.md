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
| `server/` | Server tooling: caddy image + `caddy-manage`, restic backup image |
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
git unless the directory is un-ignored (`!server/backup/`) or force-added.

- `server/caddy/Dockerfile` - Caddy + cloudflare DNS plugin
- `server/caddy-manage` - Caddyfile read/write/deploy tool (`caddy-manage help`)
- `server/backup/` - restic offsite backup of bastion Docker volumes to B2
  - **[`server/backup/RESTORE.md`](server/backup/RESTORE.md) - restore runbook, read this first**
  - [`server/backup/MONITORING.md`](server/backup/MONITORING.md) - OpenObserve alert setup
  - `run-backup.sh` (`init|backup|prune|check`), `crontab`, `excludes`, `Dockerfile`
- `.github/workflows/docker-build.yml` - matrix build of both images to GHCR as
  `ghcr.io/nperez0111/nixos-config-{caddy,backup}:main`. Adding an image means
  creating `server/<name>/Dockerfile` and adding `<name>` to `matrix.image`.

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
