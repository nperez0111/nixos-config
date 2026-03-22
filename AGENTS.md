# AGENTS.md - NixOS/nix-darwin Configuration

## Project Overview

This is a declarative NixOS/nix-darwin configuration that manages:
- Mac Mini (darwin/aarch64-darwin)
- NixOS desktop (nixos)
- VM configurations (vm/)
- Homebrew packages (darwin)
- Home Manager configurations (common)
- Custom nix overlays

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `flake.nix` | Single flake defining all outputs (darwinConfigurations, nixosConfigurations) |
| `darwin/` | MacOS/nix-darwin configuration |
| `nixos/` | NixOS desktop configuration |
| `common/` | Shared configurations across all systems |
| `vm/` | VM-specific NixOS configurations |
| `overlays/` | Custom nixpkgs overlays |
| `bin/` | Build scripts and utilities |
| `hardware/` | Hardware-specific NixOS configurations |
| `secrets/` | Age-encrypted secrets (agenix) |
| `server/` | Server/docker compose files and backups |

## Finding Things

### Darwin Configuration (Mac Mini)
- `darwin/default.nix` - Main system config, imports common, home-manager, skhd
- `darwin/home-manager.nix` - User-level config, homebrew, dock
- `darwin/brews.nix` - Homebrew CLI packages (opencode, mcfly, direnv, etc.)
- `darwin/casks.nix` - Homebrew GUI apps (brave, orion, orbstack, raycast, etc.)
- `darwin/packages.nix` - Nix packages for darwin (dockutil, skhd)
- `darwin/dock/default.nix` - Declarative dock configuration

### NixOS Configuration
- `nixos/default.nix` - Main NixOS config, X11, bspwm, picom, syncthing, emacs
- `nixos/config/` - Window manager configs (bspwmrc, sxhkdrc, polybar, rofi)
- `nixos/home-manager.nix` - NixOS user-level config
- `nixos/packages.nix` - Additional NixOS packages

### Shared/Common
- `common/default.nix` - nixpkgs config (allowUnfree, allowBroken)
- `common/home-manager.nix` - Shared shell, git, vscode, tmux, gh configs
- `common/packages.nix` - Shared packages (bat, fzf, gh, ripgrep, etc.)
- `common/files.nix` - Shared dotfiles (git template, gh hosts)
- `common/cachix/default.nix` - Cachix configuration

### Build Scripts
- `bin/build` - Auto-detects platform and runs darwin-build or nixos-build
- `bin/darwin-build` - Builds darwin configuration
- `bin/nixos-build` - Builds NixOS configuration
- `bin/update` - Updates flake inputs
- `bin/backup` / `bin/restore` - Backup utilities

### VM Configurations
- `vm/docker-host/` - Docker host VM (192.168.0.223)
- `vm/syncthing/` - Syncthing VM (192.168.0.215)

### Secrets (agenix)
- `secrets/secrets.nix` - Secret definitions
- `secrets/github` - GitHub token (age-encrypted)

## Important Users
- Darwin: `nickthesick`
- NixOS desktop: `dustin`
- VMs: `dustin`

## Build Commands
```sh
./bin/build           # Build for current platform
./bin/darwin-build   # Build darwin config
./bin/nixos-build     # Build NixOS config
nix flake update      # Update flake inputs
```

## Notes
- User identity: Nick the Sick <nick@nickthesick.com>
- GPG key: `0AD7F8215DF25741E7DC79F3420226D226E30AF2`
- SSH keys: stored in `secrets/ssh_pub`
- Uses spaceship-prompt for zsh
- Uses bspwm/sxhkd on NixOS, skhd on darwin
- Emacs runs as a daemon on NixOS
