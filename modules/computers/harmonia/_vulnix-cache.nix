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
#     (09:10 local, after NIST's overnight enrichment). The vehicle
#     is a drift-scan of harmonia's own closure with the repo
#     whitelist — exit 2 (findings) is logged and normalized: the
#     authoritative drift detector is the GitHub vulnix-drift
#     workflow; this is a free second opinion in the journal.
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
# The cache is public data (a parsed NVD mirror), so the directory is
# world-readable for nginx; growth is ZODB-append-only but tiny after
# the first pull (the modified feed adds KBs/day) — if it ever bloats,
# stop the timer, `rm -rf /var/lib/vulnix-nvd/nvd`, and let the next
# run re-pull. Not under nix.gc's reach (/var/lib, not the store), so
# the harmonia no-GC assertion is unaffected.
{ pkgs, ... }:

{
  systemd.services.vulnix-nvd-warm = {
    description = "Refresh the shared vulnix NVD feed cache (and drift-scan this host)";
    documentation = [ "https://github.com/ryanbas21/nixos-configuration/blob/main/docs/programs/security.md" ];
    # Timer-driven only, never wanted at boot: the fresh-boot VM test
    # (harmonia/vm-test.nix) has no NIST reachability, and warmth is
    # not a boot concern.
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "vulnix-nvd";
      StateDirectoryMode = "0755"; # nginx traverses+reads; the data is public
    };
    script = ''
      rc=0
      ${pkgs.vulnix}/bin/vulnix -C --cache-dir /var/lib/vulnix-nvd/nvd -w ${../../../security/vulnix-whitelist.toml} /run/current-system || rc=$?
      if [ "$rc" -eq 2 ]; then
        echo "vulnix-nvd-warm: feed refreshed; unwhitelisted findings above — triage per docs/programs/security.md (exit 2 normalized, the vulnix-drift workflow owns detection)" >&2
        exit 0
      fi
      exit "$rc"
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
