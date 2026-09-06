# Wifi MAC-address privacy (base tier — NetworkManager is the
# network stack there).
#
# "stable": NetworkManager derives a different MAC per SSID, kept
# consistent across reconnects to that network. Cross-network tracking
# via the hardware MAC dies; captive portals, per-device router
# preferences, and DHCP leases keep working (unlike "random", which
# rotates per connection and trips hotel/coffee-shop logins).
# Mullvad (framework) covers the same concern at the network layer
# when the tunnel is up; this covers every network the hardware joins.
{ ... }:
{
  nixos.modules.base.networking.networkmanager.wifi.macAddress = "stable";
}
