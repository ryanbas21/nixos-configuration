# btrfs timeline snapshots with bounded retention (snapper), for the
# desktop-style hosts. The third leg of the recovery story: nixpkgs
# generations roll back the SYSTEM, borgmatic restores FILES from the
# NAS — snapper fills the gap between them with instant LOCAL
# point-in-time copies (a fat-fingered `rm` in ~ at 14:03 is a 5-second
# rollback, not a borg restore over NFS, and not even subject to the
# battery-skip rules that gate borgmatic on the laptop).
#
# Why timeline-only (no pre/post): NixOS rebuilds are already atomic
# and reversible via generations/boot entries — snapper pre/post pairs
# around package operations would duplicate that. Timeline snapshots
# exist for the DATA, which nothing else snapshots locally.
#
# THE PRUNING CONTRACT (the reason this file exists): timeline limits
# below cap every config at ~19 live snapshots — 5 hourly, 7 daily,
# 4 weekly, 3 monthly, nothing older — and the daily cleanup timer
# enforces them. Snapshots cannot collect endlessly by construction;
# the digest (observability.nix) reports the live count per config as
# the drift check.
#
# Cost: btrfs CoW makes an hourly snapshot ~free for unchanged data
# (shared extents); only churn costs space, and the limits bound how
# long even churn is retained twice.
#
# LAYOUT (identical on both hosts — verified on the running desktop
# 2026-09-06): / is the filesystem TOP-LEVEL (subvolid 5), with `home`
# and `nix` nested subvolumes. So the `root` config (SUBVOLUME=/)
# snapshots /etc, /var, /root — everything except the nested subvols,
# which btrfs excludes from parent snapshots automatically: /home is
# covered by its own config, /nix deliberately by none (the store is
# content-addressed, rebuilt, and duplicated in every generation).
# The .snapshots dirs themselves are created AS SUBVOLUMES by the
# ensure-units below — a plain directory would be captured by every
# parent snapshot (top-level / has no parent, but /home would grow
# its .snapshots into each snapshot); as subvols they are excluded
# like any nested subvolume.
#
# BORG INTERPLAY — an invariant, not an accident: borgmatic's sources
# (batman/backup.nix) are /home/batman and /etc/nixos, and both
# configs keep .snapshots at / and /home — siblings, never parents.
# Snapshots are therefore invisible to borg BY CONSTRUCTION. Never
# point a snapper config at a path inside a borgmatic source: hourly
# CoW trees would balloon the archive (the exact "collecting
# endlessly" failure, relocated to the NAS).
#
# Base tier only: harmonia is ext4 (and skips the base anyway).
# SKIPPING /nix: see above.
{ lib, inputs, ... }:

let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  timeline = {
    FSTYPE = "btrfs";
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    TIMELINE_LIMIT_HOURLY = 5;
    TIMELINE_LIMIT_DAILY = 7;
    TIMELINE_LIMIT_WEEKLY = 4;
    TIMELINE_LIMIT_MONTHLY = 3;
    TIMELINE_LIMIT_QUARTERLY = 0;
    TIMELINE_LIMIT_YEARLY = 0;
  };

  # snapper's NixOS module writes /etc/snapper/configs/* declaratively
  # but does NOT create the .snapshots subvolumes those configs
  # require ("This path... has to contain a subvolume named
  # .snapshots" — module option docs). These idempotent one-shots do
  # it at boot. The findmnt guard keeps them no-ops on non-btrfs
  # roots (the VM boot tests' default root disk) instead of failures.
  ensureSubvolume = path: {
    description = "Ensure ${path}/.snapshots subvolume for snapper";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ "$(findmnt -n -o FSTYPE ${path})" = btrfs ] \
        && ! ${lib.getExe' pkgs.btrfs-progs "btrfs"} subvolume show ${path}/.snapshots >/dev/null 2>&1; then
        ${lib.getExe' pkgs.btrfs-progs "btrfs"} subvolume create ${path}/.snapshots
      fi
    '';
  };
in
{
  nixos.modules.base = {
    services.snapper = {
      # Both explicit for self-documentation (hourly is the module
      # default); the limits above are what bound growth.
      snapshotInterval = "hourly";
      cleanupInterval = "daily";
      configs = {
        root = timeline // { SUBVOLUME = "/"; };
        home = timeline // { SUBVOLUME = "/home"; };
      };
    };

    systemd.services = {
      snapper-ensure-root = ensureSubvolume "/";
      snapper-ensure-home = ensureSubvolume "/home";
    };
  };
}
