# Nix daemon access ACL: who may drive the local nix daemon at all.
#
# The gap this closes (found via xeiaso.net/blog/paranoid-nixos-2021-07-18,
# read 2026-09-07): nixpkgs defaults nix.settings.allowed-users to ["*"],
# meaning ANY local uid can connect to the daemon and ask it to fetch and
# execute arbitrary derivations as nixbld — a compiler-and-toolbox delivery
# service for anything that lands on the box as a non-root user. The fleet
# is single-user: batman (wheel) and root are the only humans, and nothing
# else invokes nix (the post-build-hook runs inside nix-daemon; the health
# digest/notify units never touch nix — verified 2026-09-07). Same
# "pin, don't inherit" move the fleet made for sshd PasswordAuthentication
# and the firewall: an upstream default change should not silently widen
# the ACL.
#
# trusted-users (base.nix: @wheel + implicit root) is the stronger tier
# (substituter choice, post-build-hook); this file gates the entry door
# below it. nixbld users never appear here — build workers are forked by
# the daemon, they don't connect as clients.
{ ... }:

{
  nixos.modules.base = {
    nix.settings.allowed-users = [
      "root"
      "@wheel"
    ];
  };
}
