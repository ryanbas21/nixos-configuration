# NixOS configuration

Clone-and-run configuration for every machine in the fleet: a NixOS desktop
(host `nixos`, user batman), a NixOS Framework laptop (host `framework`,
user batman), a CachyOS laptop (standalone home-manager as ryan), an
Intel Mac (standalone home-manager as ryan), and the harmonia
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
| Framework laptop (host `framework`, user batman) | NixOS | `nixosConfigurations.framework` | `cd /etc/nixos && git pull && sudo nixos-rebuild switch --flake .#framework` |
| CachyOS laptop (user ryan) | Arch-based Linux | `homeConfigurations.ryan-linux` | `nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-linux` |
| Intel Mac (user ryan) | macOS + nix | `homeConfigurations.ryan-intel-mac` | `nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-intel-mac` |
| Harmonia cache server (192.168.1.82) | NixOS, headless | `nixosConfigurations.harmonia` | from the desktop: `sudo nixos-rebuild switch --flake .#harmonia --target-host root@192.168.1.82` |

On the desktop the repo lives at `/etc/nixos`; the laptop and Mac need
nothing but nix installed. **Bringing up a machine from bare metal?** Start
with [docs/bootstrap.md](docs/bootstrap.md) — it lists the handful of
identity keys that must be restored from 1Password before the first
rebuild (everything else is in this repo).

### Fresh metal

The vehicle is always a **flash drive with the NixOS ISO** — it boots
a live NixOS that runs the install (get online with `nmtui` first).

**Step zero — install with the caches.** The ISO's (and the fresh
install's) nix only knows `cache.nixos.org`, so a naive install
**compiles the pinned-input packages from source** — the llm-agents
tools alone (pi and friends build node native modules via node-gyp)
froze a laptop install twice. Paste this **once**, before running any
command below (home LAN; also kept as a 1Password note,
"nixos-install — substituters"):

```sh
export NIX_CONFIG='
substituters = http://192.168.1.82:5000 https://nix-configs.cachix.org https://psysonic.cachix.org https://vicinae.cachix.org https://cache.numtide.com https://cache.nixos.org
trusted-public-keys = nix-cache-1:SpVt1hjpAaEgQqnY1cIm5tjTETZbG5dQmGZ3rDbTyJc= nix-configs.cachix.org-1:7Ujoj71uBp3xoxOBwPF8CTJAmoaz0+I/Dm1yK0dNyBw= psysonic.cachix.org-1:M9cQyQ7tgvUWOQ5Pyt8ozlMoPLtOZir6MfRuTH9/VYA= vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc= niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
'
```

Three rules:

- **`sudo` scrubs the environment** — that is why the commands below
  carry `sudo -E`; without it the export dies at the sudo boundary and
  the install is back to compiling from source.
- **Off the LAN?** Delete the `192.168.1.82:5000` URL and the
  `nix-cache-1:` key — an unreachable first substituter only adds
  latency, and `nix-configs` still carries what CI builds.
- **ISO's nix predates flakes** (disko / `nix run` errors about
  experimental features)? Add one more line to the same export:
  `experimental-features = nix-command flakes`. Recent official ISOs
  ship with it enabled, and the installed system sets it permanently
  (`modules/system/base.nix`) — this line is install-time only.

With the export in place, the closure substitutes from
harmonia/nix-configs/numtide in minutes; the full story (why, the CI
cache pushes, the post-build hooks) is in
[nix caches](docs/programs/nix-caches.md#installing-with-the-caches-fresh-metal--first-rebuild).

From there, two paths (details, the mental model, and the post-boot
layer in [bootstrap](docs/bootstrap.md)):

- **disko wipe** — for hosts whose disk layout is repo state (the
desktop and the framework laptop both:
`modules/computers/<host>/_disko.nix` → `diskoConfigurations.<host>`;
partitioning is declarative, no manual steps, ever):

  ```sh
  nix run github:nix-community/disko -- -m destroy,format,mount \
    -f github:ryanbas21/nixos-configuration#nixos

  # identity: the keys from 1Password, onto the target
  install -D -m 600 <id_borg>   /mnt/home/batman/.ssh/id_borg
  install -D -m 600 <git>       /mnt/home/batman/.ssh/git
  install -D -m 600 <harmonia>  /mnt/home/batman/.ssh/harmonia

  sudo -E nixos-install --flake github:ryanbas21/nixos-configuration#nixos
  sudo nixos-enter -- chown -R batman: /home/batman/.ssh
  sudo reboot
  ```

- **ISO installer, then adopt** — the fallback for a host with no
  `_disko.nix` yet (none today; the framework laptop used this once,
  2026-09-05, before its layout mirror landed): install NixOS from
  the flash drive the installer's own way, restore the keys, clone
  the repo, and switch to the flake —
  [fresh laptop runbook](docs/bootstrap.md#fresh-laptop-runbook-framework-nixos-from-the-flash-drive).

Both host configurations are **boot-tested in CI** on every push
(`modules/vm-tests.nix` → the `test-hosts` job): the real `nixos` and
`framework` modules boot as UEFI VMs and must reach multi-user.target
with the full home-manager activation — the fresh-install guarantee,
automated ([integration-testing pattern](https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines)).
The **disk layouts** are tested one level deeper (`modules/disko-tests.nix`
→ the `test-disko` job): every `_disko.nix` is executed against a
scratch VM disk and the result is booted — the labels contract as a
test.

## Documentation

All documentation lives in [`docs/`](docs/). Start with the
[architecture overview](docs/architecture.md), or jump straight to what you
need:

**Using the repo**

- [Architecture](docs/architecture.md) — how the flake is assembled, the
  option namespaces, the rules of the pattern, and the complete file tour.
- [Machines](docs/machines.md) — the four machines, and how to add a
  fifth (NixOS host or standalone box).
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
- [Backups](docs/programs/backup.md) — borgmatic to the NAS; the
  config half is the repo itself, pushed by hand.
- [Nix caches](docs/programs/nix-caches.md) — the personal cachix cache,
  the LAN harmonia server (now a tracked host), substituter order, and
  CI cache pushes.
- [Maintenance](docs/programs/maintenance.md) — weekly GC, store
  optimisation, boot-entry caps.
- [Disk layout (disko)](docs/programs/disko.md) — declarative
  partitioning and the labels contract.
- [DNS & time](docs/programs/dns-and-time.md) — systemd-resolved, ntpd-rs,
  and why the timezone is static (the Singapore saga).
- [Security](docs/programs/security.md) — sudo-rs, paretosecurity, sshd,
  and the pre-trusted GitHub host key.
- [Virtualization](docs/programs/virtualization.md) — rootless docker and
  VirtualBox.
- [Vicinae](docs/programs/vicinae.md) — the desktop launcher and its
  setcap wrapper.
- [Desktop apps](docs/programs/desktop-apps.md) — Plasma, pipewire,
  ghostty, kodi, hypnotix, obsidian, Night Light, kooha, 1Password.
- [Hyprland](docs/programs/hyprland.md) — the second Wayland session:
  xmonad muscle memory on SUPER, the everforest rice, and the 0.56
  gotchas (hyprlang-vs-Lua, the donation nag, the uwsm entry).
- [AI agents](docs/programs/agents.md) — pi and the llm-agents tools
  bundle, model routing, the ZAI key.
- [Identity](docs/programs/identity.md) — git signing, GPG auto-import,
  the SSH key inventory, gh.
- [Observability](docs/programs/observability.md) — the ntfy push server
  on harmonia, failure hooks, the weekly health digest, earlyoom, sysstat,
  journald cap, and the rack-UPS watcher.
- [Snapshots](docs/programs/snapshots.md) — snapper timelines on the btrfs
  subvols with bounded retention; the local leg of the recovery story.
- [Laptop power](docs/programs/laptop-power.md) — the framework's charge
  ceiling, power-profiles, the s2idle pin, wifi MAC privacy, and the
  USBGuard runbook (present but not enabled).

## Quick orientation

```
.
├── flake.nix / outputs.nix      inputs only; mkFlake + import-tree of ./modules
├── flake.lock                   locked input revisions (the reproducibility anchor)
├── modules/                     every .nix file = one feature (auto-imported)
│   ├── computers/               per-host data (+ _hardware.nix mounts,
│   │                            _disko.nix layouts, harmonia vm-test)
│   ├── system/                  the system tier: the shared base layer the
│   │                            desktop-style hosts import (harmonia skips)
│   ├── batman/                  user-level features (shell, nvf, backups, ...)
│   ├── vm-tests/                throwaway identity + .age secrets the CI
│   │                            boot tests decrypt (real keys: 1Password)
│   ├── disko.nix                disk layouts exported to the disko CLI
│   ├── disko-tests.nix          every _disko.nix executed + booted in a VM
│   ├── vm-tests.nix             fresh-boot VM tests (CI boots every host)
│   └── *.nix                    machinery (users, home, eval-modules, ...)
├── secrets/ + secrets.nix       agenix-encrypted secrets (safe to commit)
├── scripts/                     host-adoption helper (adopt-harmonia.sh)
└── .github/workflows/ci.yml     eval-only flake check + standalone home builds
```

Rules in one breath: drop a file to enable it; `/_` in a path means
manual-import; feature files never import each other, they only assign to
option namespaces; lower-level modules are stored as data
(`deferredModule`) and fed to the real evaluations by the machinery files.
The full explanation is in [architecture](docs/architecture.md).
