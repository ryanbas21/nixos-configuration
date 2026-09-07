{
  nixos.modules.base = {
    services.resolved = {
      enable = true;
      # LLMNR off (sweep finding 2026-09-07, xeiaso paranoid-nixos read):
      # with resolved's default LLMNR=yes it listens on 0.0.0.0:5355 on
      # EVERY link (verified live with resolvectl). LLMNR is a spoofable
      # legacy name-resolution protocol with zero speakers on this fleet —
      # no Windows machines, hosts are addressed by IP/DNS — so the
      # listener is pure surface. The firewall already blocks it; this
      # closes it at the daemon instead of trusting firewall rules to
      # outlive an accident. NOTE the spelling: same gperf all-caps key
      # table as DNSOverTLS below (the old services.resolved.llmnr option
      # was renamed here in this nixpkgs).
      settings.Resolve.LLMNR = "false";
      settings.Resolve = {
        # NOTE the spelling: systemd's gperf key table (and the NixOS
        # option) is DNSOverTLS, all caps — a differently-cased key is an
        # unknown lvalue that resolved silently ignores (leaving DoT at
        # the module default "false").
        DNSOverTLS = "opportunistic";
        DNS = [
          # pihole
          "192.168.1.39"
          # mullvad extended (ad/tracker blocking)
          "extended.dns.mullvad.net"

          # quad9
          "9.9.9.9"

          # https://developers.cloudflare.com/1.1.1.1
          "1.0.0.1"
          "2606:4700:4700::1111"
          "2606:4700:4700::1001"
        ];
      };
    };
  };
}
