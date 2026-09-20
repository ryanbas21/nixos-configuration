# Self-hosted vulnix NVD feed warmth for the LAN.
#
# vulnix refreshes its NVD feed over the network on every run (a
# sandboxed Nix build cannot, which is why the scan is a `nix run`
# wrapper, not a check — see modules/vulnix.nix). A cold cache pays
# the FULL feed download from NIST (~2 GB of JSON, several minutes,
# anonymous rate limits); a warm one pays a single small `modified`
# delta. This feature makes harmonia the fleet's warmth source, the
# same role it already plays for nix store paths:
#
#   - vulnix-nvd-warm.timer refreshes /var/lib/vulnix-nvd/nvd nightly
#     (09:10 local, after NIST's overnight enrichment).
#   - nginx serves the cache directory read-only on :8088, scoped to
#     the home subnet by nftables like sshd/harmonia themselves
#     (runners cannot reach the LAN by design — CI keeps its own
#     NIST + actions/cache path and sets VULNIX_NVD_MIRROR="").
#   - The vulnix-scan wrapper on every host copies the mirror's
#     Data.fs when newer (curl -z → 304s are free on nginx), then
#     runs vulnix as usual: last_update < 7d means clients fetch only
#     the `modified` feed from NIST directly, keeping freshness
#     between warm runs.
#
# Why the warm job is `-f /dev/null` and NOT a closure scan: this box
# never builds its own system — deploys arrive as copied OUTPUT paths
# (`nixos-rebuild --target-host`), which carry deriver *metadata* but
# no .drv files, so vulnix's -C mode (it shells `nix derivation show`)
# dies with DeriverLookupError on the toplevel (proven 2026-09-20,
# 385ms into the first run). Shipping .drv closures or building on
# the cache host were both rejected; the NVD update is the only thing
# this job needs, and it runs before the (empty) scan regardless.
# Drift detection for harmonia's pin stays where it already lives:
# CI's build-hosts + vulnix jobs scan the exact pin nightly.
#
# Why root with a plain directory, not DynamicUser + StateDirectory
# (both burned on first deploy, 2026-09-20): systemd routes dynamic
# users' state dirs to /var/lib/private — mode 0700 root — behind a
# compatibility symlink at /var/lib/<name>, so nginx (or any non-root
# reader) gets EACCES through the symlink no matter the file modes.
# With no closure walk there is no daemon need either, so the unit is
# simply root + a strict sandbox pinned to one writable path; the
# directory is world-readable because the data is public.
#
# The cache is public data (a parsed NVD mirror), so the directory is
# world-readable for nginx; growth is ZODB-append-only but tiny after
# the first pull (the modified feed adds KBs/day) — if it ever bloats,
# stop the timer, `rm -rf /var/lib/vulnix-nvd/nvd`, and let the next
# run re-pull. Not under nix.gc's reach (/var/lib, not the store), so
# the harmonia no-GC assertion is unaffected.
{ pkgs, ... }:

{
  systemd.services.vulnix-nvd-warm = {
    description = "Refresh the shared vulnix NVD feed cache";
    documentation = [ "https://github.com/ryanbas21/nixos-configuration/blob/main/docs/programs/security.md" ];
    # Timer-driven only, never wanted at boot: the fresh-boot VM test
    # (harmonia/vm-test.nix) has no NIST reachability, and warmth is
    # not a boot concern.
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = "read-only";
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/vulnix-nvd" ];
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
    # No closure to walk → no nix daemon: the feed update is the
    # entire job (see header).
    script = ''
      mkdir -p /var/lib/vulnix-nvd/nvd
      ${pkgs.vulnix}/bin/vulnix --cache-dir /var/lib/vulnix-nvd/nvd -f /dev/null
    '';
  };

  systemd.timers.vulnix-nvd-warm = {
    description = "Nightly vulnix NVD feed refresh";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 09:10:00"; # local time (America/Denver, set in harmonia.nix)
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };

  services.nginx = {
    # Bare static file server — deliberately no recommended_* kitchen
    # sink: one read-only location serving one public file, LAN-scoped
    # by the nftables rule below (nginx binds 0.0.0.0 for the same
    # reason harmonia's daemon binds [::]: the firewall is the scope,
    # and a literal-LAN-IP bind would break the VM test's interfaces).
    enable = true;
    virtualHosts."vulnix-nvd" = {
      listen = [ {
        addr = "0.0.0.0";
        port = 8088;
      } ];
      root = "/var/lib/vulnix-nvd/nvd";
      locations."/" = {
        extraConfig = ''
          autoindex off;
        '';
      };
    };
  };

  networking.firewall.extraInputRules = ''
    ip saddr 192.168.1.0/24 tcp dport 8088 accept
  '';
}
