# Nix store maintenance, both NixOS hosts: garbage collection, store
# optimisation, boot-entry retention.
#
# Why this exists: the desktop accumulated 2,397 system generations and
# 109 boot-menu entries in ~5 days of eval loops, with nothing ever
# pruned — unbounded growth (see docs/programs/maintenance.md).
#
# Assigned twice, deliberately: the desktop eats nixos.modules.base,
# but the harmonia host runs its own minimal base (computers/harmonia.nix
# imports neither the base nor a user slot) while still accumulating a
# generation per remote deploy — so it receives the same retention
# directly into its host module. If a server tier (nixos.modules.server)
# is ever promoted out of the harmonia host file, fold this into it.
{ ... }:
let
  retention = {
    # Weekly GC: deletes generations (and their boot entries) older than
    # 30 days. Covers the system profile AND per-user profiles under
    # /nix/var/nix/profiles — batman's home-manager generations live
    # there (useUserPackages), so one root timer covers both. Rollback
    # reach becomes bounded by exactly this knob (docs/operations.md,
    # "Rollback & failure recovery").
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # Hardlink identical store paths as they are written; with the eval
    # loops this machine runs, dedup pays for itself quickly.
    nix.settings.auto-optimise-store = true;

    # Cap the systemd-boot menu at the 10 newest generations; the next
    # rebuild prunes the existing backlog on the ESP.
    boot.loader.systemd-boot.configurationLimit = 10;
  };
in
{
  nixos.modules.base = retention;

  nixos.configurations.harmonia.module = retention;
}
