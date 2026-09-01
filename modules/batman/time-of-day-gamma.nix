# Day/night screen gamma via gammastep, driven by geoclue2 location.
# home.pc (not home.base): GUI/Wayland-only, must stay off the standalone
# Mac export. gammastep's geoclue2 provider registers with the geoclue
# daemon under DesktopId "gammastep", which geoclue denies unless it is
# whitelisted — hence the appConfig half below.
{ ... }:

{
  users.batman.home.pc = {
    services.gammastep = {
      enable = true;
      provider = "geoclue2";
      tray = true;
    };
  };

  # NixOS half: allow gammastep to query geoclue2. The daemon itself is
  # enabled by services.automatic-timezoned (modules/time.nix); mkDefault
  # keeps this module self-sufficient without fighting that assignment.
  nixos.modules.base = { lib, ... }: {
    services.geoclue2 = {
      enable = lib.mkDefault true;
      appConfig.gammastep = {
        isAllowed = true;
        isSystem = false;
        users = [ "batman" ];
      };
    };
  };
}
