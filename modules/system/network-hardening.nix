# Network-layer sysctl hardening (base tier; harmonia's minimal base
# skips it — a static-IP, root-only LAN box opts in only if it wants).
#
# The gap this file closes (verified live 2026-09-07 on the framework):
# accept_redirects was permissive at the per-interface layer. The
# kernel takes the MAX of the "all" and per-interface values for
# accept_redirects, so all=0 alone protects nothing — and interfaces
# created AFTER boot (every wlan association, docker bridges, VPN
# interfaces) inherit the "default" value, which was 1: a host that
# roams onto hostile wifi accepts ICMP redirects from it. Redirects
# are an on-path attacker's route-hijack primitive; there is no
# legitimate use on any network this fleet joins.
#
# rp_filter is deliberately LOOSE (2), not strict (1): loose still
# drops martian sources but tolerates asymmetric routing, which both
# docker's bridge plumbing and Mullvad's fwmark tunnels can produce.
# Strict is one edit away if the posture ever warrants it.
{ ... }:

{
  nixos.modules.base = {
    boot.kernel.sysctl = {
      # ICMP redirects: kill them at BOTH layers, v4 and v6 (the
      # max(all, iface) rule is why "default" must be zeroed too).
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;

      # Don't send redirects either (a host is not a router here).
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;

      # Source-routed packets: kernel default is already 0 on this
      # kernel — pinned so it stays that way, at both layers.
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.default.accept_source_route" = 0;

      # Loose reverse-path filtering + martian logging: spoofed-source
      # packets drop (and leave a journal trace) without breaking the
      # asymmetric paths docker/Mullvad create.
      "net.ipv4.conf.all.rp_filter" = 2;
      "net.ipv4.conf.default.rp_filter" = 2;
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.default.log_martians" = 1;
    };
  };
}
