# NixOS configuration

Clone-and-run configuration for every machine in the fleet: a NixOS desktop
(host `nixos`, user batman), a CachyOS laptop (standalone home-manager as
ryan), an Intel Mac (standalone home-manager as ryan), and the harmonia
cache server on the LAN (NixOS, headless). The repo is
organized as one feature per file: dropping a `.nix` file into `modules/` is
the only step needed to enable it. Neovim is built by nvf, with its lua
sourced from the dotfiles repo through the `ryan-nvim` flake input.

[![CI](https://github.com/ryanbas21/nixos-configuration/actions/workflows/ci.yml/badge.svg)](https://github.com/ryanbas21/nixos-configuration/actions/workflows/ci.yml)

The structure follows the [dendritic pattern](https://github.com/mightyiam/dendritic);
[mightyiam/infra](https://github.com/mightyiam/infra) is the canonical
implementation.

## Machines

| Machine | OS | Consume via | Command |
|---|---|---|---|
| Desktop (host `nixos`, user batman) | NixOS | `nixosConfigurations.nixos` | `cd /etc/nixos && git pull && sudo nixos-rebuild switch --flake .#nixos` |
| CachyOS laptop (user ryan) | Arch-based Linux | `homeConfigurations.ryan-linux` | `nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-linux` |
| Intel Mac (user ryan) | macOS + nix | `homeConfigurations.ryan-intel-mac` | `nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-intel-mac` |
| Harmonia cache server (192.168.1.82) | NixOS, headless | `nixosConfigurations.harmonia` | from the desktop: `sudo nixos-rebuild switch --flake .#harmonia --target-host root@192.168.1.82` |

On the desktop the repo lives at `/etc/nixos`; the laptop and Mac need
nothing but nix installed. **Bringing up a machine from bare metal?** Start
with [docs/bootstrap.md](docs/bootstrap.md) — it lists the handful of
identity keys that must be restored from 1Password before the first
rebuild (everything else is in this repo).

## Documentation

All documentation lives in [`docs/`](docs/). Start with the
[architecture overview](docs/architecture.md), or jump straight to what you
need:

**Using the repo**

- [Architecture](docs/architecture.md) — how the flake is assembled, the
  option namespaces, the rules of the pattern, and the complete file tour.
- [Machines](docs/machines.md) — the three machines, and how to add a
  fourth (NixOS host or standalone box).
- [Operations](docs/operations.md) — the input-update ritual, deployment
  steady state, hardware changes, and what CI checks.
- [Bootstrap & recovery](docs/bootstrap.md) — **the reproducibility
  contract**: exactly what is (and is not) in the repo, the SSH key
  inventory, and ordered runbooks for a fresh desktop, laptop, and Mac.
- [Secrets (agenix)](docs/secrets.md) — how secrets are encrypted,
  committed, and added.

**Program notes** ([index](docs/programs/index.md))

System-level things that are not obvious from the code alone — what each
program does, why it is there, and the war stories:

- [Neovim (nvf)](docs/programs/neovim.md) — the nvf + dotfiles-lua bridge.
- [Shell & CLI](docs/programs/shell-and-cli.md) — fish, fzf, starship,
  zoxide, carapace, eza, direnv, and the package inventory.
- [Backups](docs/programs/backup.md) — borgmatic + the daily git-backup
  timer.
- [Nix caches](docs/programs/nix-caches.md) — the personal cachix cache,
  the LAN harmonia server (now a tracked host), substituter order, and
  CI cache pushes.
- [Maintenance](docs/programs/maintenance.md) — weekly GC, store
  optimisation, boot-entry caps.
- [DNS & time](docs/programs/dns-and-time.md) — systemd-resolved, ntpd-rs,
  and why the timezone is static (the Singapore saga).
- [Security](docs/programs/security.md) — sudo-rs, paretosecurity, sshd,
  and the pre-trusted GitHub host key.
- [Virtualization](docs/programs/virtualization.md) — rootless docker and
  VirtualBox.
- [Vicinae](docs/programs/vicinae.md) — the desktop launcher and its
  setcap wrapper.
- [Desktop apps](docs/programs/desktop-apps.md) — Plasma, pipewire,
  ghostty, kodi, obsidian, gammastep, kooha, 1Password.
- [AI agents](docs/programs/agents.md) — pi and the llm-agents tool
  bundle, model routing, the ZAI key.
- [Identity](docs/programs/identity.md) — git signing, GPG auto-import,
  the SSH key inventory, gh.

## Quick orientation

```
.
├── flake.nix / outputs.nix      inputs only; mkFlake + import-tree of ./modules
├── flake.lock                   locked input revisions (the reproducibility anchor)
├── modules/                     every .nix file = one feature (auto-imported)
│   ├── computers/               per-host data (+ _hardware.nix mounts,
│   │                            _disko.nix layouts)
│   ├── nixos/                   the shared system base
│   ├── batman/                  user-level features (shell, nvf, backups, ...)
│   └── *.nix                    machinery (users, home, eval-modules, ...)
├── secrets/ + secrets.nix       agenix-encrypted secrets (safe to commit)
├── scripts/git-backup.sh        what the daily config-backup timer runs
└── .github/workflows/ci.yml     eval-only flake check + standalone home builds
```

Rules in one breath: drop a file to enable it; `/_` in a path means
manual-import; feature files never import each other, they only assign to
option namespaces; lower-level modules are stored as data
(`deferredModule`) and fed to the real evaluations by the machinery files.
The full explanation is in [architecture](docs/architecture.md).
