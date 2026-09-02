# Machines

[← README](../README.md) · [Architecture](architecture.md) · [Operations](operations.md)

The fleet and how to extend it.

| Machine | OS | Consume via | Command |
|---|---|---|---|
| Desktop (host `nixos`, user batman) | NixOS | `nixosConfigurations.nixos` | `cd /etc/nixos && git pull && sudo nixos-rebuild switch --flake .#nixos` |
| CachyOS laptop (user ryan) | Arch-based Linux | `homeConfigurations.ryan-linux` | `nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-linux` |
| Intel Mac (user ryan) | macOS + nix | `homeConfigurations.ryan-intel-mac` | `nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-intel-mac` |
| Harmonia cache server (192.168.1.82) | NixOS, headless | `nixosConfigurations.harmonia` | from the desktop: `sudo nixos-rebuild switch --flake .#harmonia --target-host root@192.168.1.82` |

On the desktop the repo lives at `/etc/nixos` — a symlink to
`~/programming/nixos`, the actual checkout — so the steady state is
`git pull` followed by the rebuild command above; the laptop and Mac need
nothing but nix installed. The desktop's git-backup timer operates on
that checkout (the path is bound once, as `repoPath`, in
`modules/batman/backup.nix`), so moving the checkout means changing
that binding.

### The harmonia host — the slim variant

`modules/computers/harmonia.nix` (the cache server) demonstrates the
departure from the standard host recipe: being headless and
single-purpose, it imports **neither** `nixos.modules.base` (no Plasma,
no home-manager, no backups) **nor** a user slot — root is the only
account, its base is a few lines inline (sshd, firewall 22+5000,
flakes), and its only secret is system-level agenix decrypted with the
ssh **host** key. It is never rebuilt on the box: deploys come from the
desktop via `--target-host` (builds locally, copies the closure over
ssh). The one-time adoption runbook and the server-side story live in
[nix caches](programs/nix-caches.md#the-server-82--tracked-in-this-repo).

Setting a machine up from bare metal (including which SSH keys must be
restored first) is covered in [bootstrap.md](bootstrap.md).

## Adding a NixOS host

1. Create `modules/computers/<name>.nix` assigning
   `nixos.configurations.<name>.module`: `system.stateVersion`,
   `nixpkgs.hostPlatform`, the machine's `networking.hostName` and any
   NFS mounts it needs (with `boot.supportedFilesystems = [ "nfs" ]` —
   host-specific data lives here, not in the shared base), and
   `imports = [ ./<name>/_hardware.nix config.nixos.modules.base config.users.<user>.nixos.base ]`.
   Use the stateVersion of the NixOS release installed on the box, and
   never change it afterwards.
2. On the box, run `nixos-generate-config`; copy the generated
   `hardware-configuration.nix` content into
   `modules/computers/<name>/_hardware.nix` (the `_` prefix is required —
   see [hardware](#hardware)), and write a matching
   `modules/computers/<name>/_disko.nix` layout plus a
   `diskoConfigurations.<name>` entry (`modules/disko.nix`).
3. Commit, then `sudo nixos-rebuild switch --flake .#<name>`.
   `nixosConfigurations.<name>` and a flake check appear automatically.

A desktop-style host is the common case, but not the only shape: a
headless box can skip `nixos.modules.base` and the user slot entirely
and carry a minimal base inline — the harmonia host
([above](#the-harmonia-host--the-slim-variant)) is the worked example.

## Adding a standalone machine (any non-NixOS box)

Add an entry to `home.configurations` in `modules/home.nix` (username,
system, homeDirectory) and commit. The Mac entry assumes username `ryan`;
if the account is named differently, change `username` in that entry.

Notes on the existing entries:

- `ryan-linux` builds against the root `nixpkgs` input (unstable).
- `ryan-intel-mac` builds against `nixpkgs-intel-mac`
  (`nixpkgs-26.05-darwin`), the last branch that ships `x86_64-darwin`,
  and carries two workarounds for that older set: a `problems.handlers`
  warn (fzf 0.72 vs fishPlugins.fzf-fish meta) and
  `programs.fzf.enableNushellIntegration = false` (home-manager master's
  fzf 0.73 floor). See the comments in `modules/home.nix`.

## Hardware

**Partitioning and hardware both live in the repo, per host.** Each
NixOS host carries two files next to its host file:

- `modules/computers/<name>/_disko.nix` — the **declarative disk
  layout** (disko), exposed flake-level as `diskoConfigurations.<name>`
  (`modules/disko.nix`) and consumed by the disko CLI on fresh metal:
  `nix run github:nix-community/disko -- -m destroy,format,mount -f
  github:ryanbas21/nixos-configuration#<name>`. Explicit partition
  **labels are the contract**: the layout sets them, and the host's
  mounts reference `/dev/disk/by-partlabel/...`, so a disko-formatted
  disk and the original hand-partitioned disk (labeled once in place —
  see [bootstrap](bootstrap.md#adopting-the-existing-disk-one-time--completed-2026-09-02))
  satisfy the identical config.
- `modules/computers/<name>/_hardware.nix` — the mount table (by
  partlabel) plus kernel facts (modules, microcode), maintained by
  hand; originally from `nixos-generate-config`.

The `_` prefix keeps import-tree from auto-importing both; the host
file imports `_hardware.nix` manually, and `_disko.nix` is deliberately
**not** in the host eval at all (no generated-mount conflicts — the
layout and the mount table are independent facts meeting at the
labels).

**When hardware changes**, scan-and-harvest — sized by what actually
changed:

| Change | To do |
|---|---|
| RAM, most USB peripherals | nothing — no config tracks them |
| GPU (same vendor class) | usually nothing; an NVIDIA card would need the driver + an unfree-allowlist entry (none today) |
| CPU/motherboard (same arch) | harvest fresh kernel facts into `_hardware.nix` (`kvm-amd` vs `kvm-intel`, microcode, initrd modules); the box still boots on the generic modules, so rebuild in place |
| Disk swapped/replaced | the ISO flow — `_disko.nix` is size-agnostic (ESP 2G + 100% rest), a bigger/new disk needs no layout edit; then borg restores the data. (Or clone the disk — the partlabels ride along.) |
| Second disk added | a `fileSystems` entry in `_hardware.nix` — do NOT add data disks to the disko layout unless `-m destroy` should wipe them too |
| Whole platform change (e.g. ARM) | also `nixpkgs.hostPlatform`, plus the `system` pins in `modules/nixos.nix` (per-host `args`) and `outputs.nix` (`systems`) |

Gotcha: on the live desktop `/etc/nixos` is the repo checkout, so a
bare `nixos-generate-config` would drop generated files into the
working tree — use `nixos-generate-config --show-hardware-config >
/tmp/hw.nix` and harvest from there. Worst case, a hardware change
that breaks boot: the ISO flow reinstalls from the repo — it is cheap
now — and the boot menu's previous generations remain the first
rollback stop.

The desktop today: systemd-boot on UEFI, 2G ESP (`nixos-ESP`) + btrfs
root (`nixos-root`), no swap, Intel CPU (`kvm-intel`), no LUKS. The
harmonia host gets its `_disko.nix` when the
[adoption runbook](programs/nix-caches.md#bringing-82-under-management-one-time)
lands a real hardware scan.
