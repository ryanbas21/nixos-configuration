# Disk layout (disko)

[← program notes](index.md) · modules: `disko.nix`, `computers/nixos/_disko.nix` · upstream: github:nix-community/disko

## What disko is

A library + CLI that turns a **declarative disk layout into reality**:
given a Nix module describing partitions, filesystems and mountpoints,
it generates and runs the scripts that partition (`sgdisk`), format
(`mkfs.*`) and mount — a declarative `fdisk` + `mkfs` + `mount`. It is
an **install-time tool only**: it never runs at boot, never touches a
running system's disk, and — in this repo — is not part of any host's
evaluation at all. It exists to remove the last human-judgment step
from a bare-metal rebuild: nobody hand-partitions anything anymore.

## The three pieces, and why they're separate

| Piece | Role |
|---|---|
| `modules/computers/nixos/_disko.nix` | the layout as data: disk `nvme0n1` → GPT → `nixos-ESP` (2G, `EF00`, vfat, `/boot`) + `nixos-root` (100%, btrfs, `/`) |
| `modules/disko.nix` | exposes it flake-level as `diskoConfigurations.nixos` — the attribute the disko CLI discovers |
| `modules/computers/nixos/_hardware.nix` | the **running** system's mount table + kernel facts, hand-maintained |

Disko ships a NixOS module that can *generate* `fileSystems` from the
layout — this repo deliberately does not use it. The layout and the
mount table are kept as **independent facts that meet at the partition
labels**, so neither can silently drift the other, and the host eval
carries no installer concerns.

## The labels contract

The layout sets explicit GPT partition names (`nixos-ESP`,
`nixos-root`); the host mounts address
`/dev/disk/by-partlabel/nixos-{ESP,root}`. Verified at eval level: the
devices disko generates for this layout are exactly the devices in
`_hardware.nix`. Why partlabel and not UUID: **UUIDs change on every
format** — by-uuid mounts break on every reinstall — while labels are
deterministic content-independent metadata. This is what makes "fresh
disko-formatted disk" and "the original hand-partitioned disk" (labels
set once in place, metadata-only `sgdisk --change-name`) satisfy the
identical configuration. The one-time adoption of the live disk is
complete (2026-09-02); the two disks are now interchangeable.

## Fresh metal

```sh
nix run github:nix-community/disko -- -m destroy,format,mount \
  -f github:ryanbas21/nixos-configuration#nixos
```

- `destroy` wipes the partition table — **the single destructive
  operation in this repo** (it also takes the dead p1/p2 leftovers
  with it);
- `format` writes the GPT, makes both filesystems, sets the labels;
- `mount` arranges `/mnt` (+ `/mnt/boot`) ready for `nixos-install`.

The rest of the flow is [bootstrap](../bootstrap.md#fresh-desktop-runbook-same-hardware).

## Validating a layout change without touching a disk

Eval the layout through disko's own module and compare the generated
devices against `_hardware.nix`:

```sh
nix eval --impure --json --expr 'let
  flake = builtins.getFlake (toString /etc/nixos);
  disko  = builtins.getFlake "github:nix-community/disko";
  ev = import "${flake.inputs.nixpkgs}/nixos/lib/eval-config.nix" {
    system = "x86_64-linux";
    modules = [ disko.nixosModules.default flake.diskoConfigurations.nixos ];
  };
in { root = ev.config.fileSystems."/".device;
     boot = ev.config.fileSystems."/boot".device; }'
```

(A bare `lib.evalModules` is not enough — disko's module defines
NixOS-level options like `assertions` and `boot`.)

This trick is the quick local diff; the full validation is automated:
the `disko:*` flake checks ([modules/disko-tests.nix](../../modules/disko-tests.nix),
CI's `test-disko` job) execute each layout for real in a VM —
partition, format, mount (idempotency checked), install a minimal
NixOS onto it, boot it as a second VM, and compare every booted mount
against `_hardware.nix`. Run one locally with `nix build -L
.#checks.x86_64-linux."disko:framework"`.

## Future

- **LUKS** landed fleet-wide with the 2026-09 rework — framework
  first (`content.type = "luks"` wrapping the btrfs, TPM2
  auto-unlock, converted in place; see
  `computers/framework/_disko.nix`'s header for the threat model and
  CI story: the disko tests unlock with the harness-seeded keyfile
  standing in for the metal TPM slot), then the desktop (same
  layout, TPM confirmed on the box; the extra driver there is
  id_borg — the borg repo's decryption key — living on that disk).
  The harmonia cache VM deliberately stays plaintext: no user
  secrets, agenix-encrypted signing key.
- The **framework laptop's** mirror landed 2026-09-06
  (`computers/framework/_disko.nix`, the fleet's first layout with
  btrfs subvolumes — and the first to use the modern
  `type = "btrfs"` spelling, required for subvolumes), then became
  the fleet's first LUKS layout (2026-09 rework; the mirror's swap
  partition went with it). The labels were renamed on the live
  installer disk in place; the same eval trick below verified the
  generated devices match `_hardware.nix` before anything shipped.
