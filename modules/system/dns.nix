{
  nixos.modules.base = {
    services.resolved = {
      enable = true;
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
