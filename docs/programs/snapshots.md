# Snapshots (snapper)

The third leg of the recovery story:

| threat | mechanism |
|---|---|
| broken system | nixpkgs generations + boot entries (rollback = reboot) |
| lost/corrupt files | borgmatic to the NAS (battery-gated on the laptop) |
| fat-fingered `rm` 20 minutes ago | **snapper — instant, local, offline-proof** |

An hourly CoW snapshot of `/` (the OS half) and `/home` (the data
half), per `modules/system/snapper.nix`.

## Retention — bounded by construction

Timeline cleanup with `5 hourly / 7 daily / 4 weekly / 3 monthly /
nothing older` ≈ **19 live snapshots per config, hard cap**; the daily
cleanup timer enforces the limits, and the digest reports the live
count per config so drift is visible. Snapshots cannot collect
endlessly; that contract is the reason the file exists.

Space cost is CoW-cheap: unchanged extents are shared between
snapshots; only churn is retained twice, for a bounded time.

## What is (and is not) snapshotted

Both desktop-style hosts share the layout (verified on the running
desktop 2026-09-06): `/` is the btrfs top-level, with `home` and `nix`
nested subvolumes. btrfs excludes nested subvolumes from parent
snapshots, so:

- `root` config (SUBVOLUME `/`): `/etc`, `/var`, `/root` — the OS
  half.
- `home` config: `/home` — the data half.
- **`/nix` deliberately none**: content-addressed, rebuilt, and
  already duplicated per-generation in the store.
- `/.snapshots` and `/home/.snapshots` are created **as subvolumes**
  by the boot-time ensure-units, precisely so they are excluded from
  the parent's snapshots (a plain directory would be captured by every
  `/home` snapshot — unbounded nesting).

Timeline-only, no pre/post: NixOS rebuilds are already atomic and
generation-reversible; pre/post pairs would duplicate that.

## Borg interplay — an invariant, not an accident

borgmatic's sources are `/home/batman` and `/etc/nixos`
(`batman/backup.nix`); both `.snapshots` dirs sit at `/` and `/home` —
**siblings, never parents** of any borg source. Snapshots are invisible
to borg by construction. Never point a snapper config into a borgmatic
source: hourly CoW trees in the archive would balloon it — the
"collecting endlessly" failure, relocated to the NAS.

## Restoring

```
sudo snapper -c home list                      # find the snapshot
sudo cp -a /home/.snapshots/<N>/snapshot/<path> /home/<path>
# or browse there directly — the trees are live read-only mounts
```

## Boot-test interplay

The VM boot tests run the real host modules but on the test
framework's non-btrfs root disk, so `services.snapper.configs` is
`mkForce {}`d in `modules/vm-tests.nix` — the same
environmental-mismatch neutralization the NFS mounts get. First-boot
verification on metal: `systemctl status snapper-ensure-root
snapper-ensure-home` (created the subvols), then after an hour,
`sudo snapper -c root list` — and a timeline failure pages the phone
(the OnFailure wiring in observability.nix).

## Not for harmonia

ext4, and the box deliberately skips the base tier.
