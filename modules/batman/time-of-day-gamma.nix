# Day/night screen gamma via gammastep with a fixed location.
# home.pc (not home.base): GUI/Wayland-only, must stay off the standalone
# Mac export.
#
# Manual coordinates, not geoclue2: the geolocation chain (geoclue ->
# beacondb) has no WiFi coverage for this location and its IP fallback
# misattributes this ISP's address to Singapore, which put the sun
# schedule 14 hours off. The machine is a stationary desktop, so these
# coordinates only need updating if it ever moves.
{ ... }:

{
  users.batman.home.pc = {
    services.gammastep = {
      enable = true;
      provider = "manual";
      latitude = "39.7392";
      longitude = "-104.9903";
      tray = true;
    };
  };
}
