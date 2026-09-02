# Machines

[← README](../README.md) · [Architecture](architecture.md) · [Operations](operations.md)

The fleet and how to extend it.

| Machine | OS | Consume via | Command |
|---|---|---|---|
| Desktop (host `nixos`, user batman) | NixOS | `nixosConfigurations.nixos` | `cd /etc/nixos && git pull && sudo nixos-rebuild switch --flake .#nixos` |
| CachyOS laptop (user ryan) | Arch-based Linux | `homeConfigurations.ryan-linux` | `nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-linux` |
| Intel Mac (user ryan) | macOS + nix | `homeConfigurations.ryan-intel-mac` | `nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-intel-mac` |

On the desktop the repo lives at `/etc/nixos` — a symlink to
`~/programming/nixos`, the actual checkout — so the steady state is
`git pull` followed by the rebuild command above; the laptop and Mac need
nothing but nix installed. The desktop's git-backup timer operates on
that checkout (the path is bound once, as `repoPath`, in
`modules/batman/backup.nix`), so moving the checkout means changing
that binding.

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
   see [hardware](#hardware)).
3. Commit, then `sudo nixos-rebuild switch --flake .#<name>`.
   `nixosConfigurations.<name>` and a flake check appear automatically.

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

**Hardware lives in the repo, per host.** The desktop's generated hardware
scan is tracked as `modules/computers/nixos/_hardware.nix` —
machine-local data, kept next to its host file. The underscore prefix
matters: the file is a NixOS module
(`imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];`) that
would infinitely recurse if import-tree auto-imported it as a flake-parts
module; the `/_` in its path keeps it manual, and
`modules/computers/nixos.nix` imports it explicitly.

**When hardware changes** (a disk swap, a new partition layout): run
`nixos-generate-config` on the machine, copy the generated
`hardware-configuration.nix` content into
`modules/computers/nixos/_hardware.nix`, and commit it.

The current scan says: systemd-boot on UEFI, btrfs root
(`/dev/disk/by-uuid/a4fad180-...`), vfat `/boot`, no swap, Intel CPU with
`kvm-intel`, no LUKS.
