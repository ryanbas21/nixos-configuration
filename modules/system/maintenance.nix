# Nix store maintenance: garbage collection, store optimisation,
# boot-entry retention.
#
# Why this exists: the desktop accumulated 2,397 system generations and
# 109 boot-menu entries in ~5 days of eval loops, with nothing ever
# pruned — unbounded growth (see docs/programs/maintenance.md).
#
# Split assignment, deliberately: the desktop-style hosts eat
# nixos.modules.base and get the full retention set, collector included.
# The harmonia host runs its own minimal base (computers/harmonia.nix
# imports neither the base nor a user slot) while still accumulating a
# generation per remote deploy — so it receives the optimise/boot-entry
# retention directly into its host module, but NEVER nix.gc: the box is
# the LAN binary cache, and every cached path is unreachable by
# definition, so any collect sweeps the cache itself
# (--delete-older-than gates generations, not the sweep). Found live
# 2026-09-07: the first weekly run deleted 7,304 paths / 38.4 GiB of
# freshly pushed cache, and the desktop's next build re-pushed the lot
# over the LAN. Disk pressure stays guarded by nix.settings.min-free
# (harmonia/_remote-builder.nix) — an in-daemon trigger that fires only
# when the store disk is nearly full. harmonia.nix carries an eval
# assertion keeping the collector off. If a server tier
# (nixos.modules.server) is ever promoted out of the harmonia host
# file, fold this in — carrying the no-GC rule with it.
{ ... }:
let
  # Weekly GC: deletes generations (and their boot entries) older than
  # 30 days, then sweeps everything the survivors no longer reference.
  # Covers the system profile AND per-user profiles under
  # /nix/var/nix/profiles — batman's home-manager generations live
  # there (useUserPackages), so one root timer covers both. Rollback
  # reach becomes bounded by exactly this knob (docs/operations.md,
  # "Rollback & failure recovery").
  gc = {
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Hardlink identical store paths as they are written; with the eval
  # loops these machines run, dedup pays for itself quickly.
  optimise = { nix.settings.auto-optimise-store = true; };

  # Cap the systemd-boot menu at the 10 newest generations; the next
  # rebuild prunes the existing backlog on the ESP.
  bootEntries = { boot.loader.systemd-boot.configurationLimit = 10; };
in
{
  nixos.modules.base = gc // optimise // bootEntries;

  # The cache host: retention minus the collector — see the header.
  nixos.configurations.harmonia.module = optimise // bootEntries;
}
