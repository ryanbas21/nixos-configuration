# Kodi media center for batman. Ported from ./home.nix (top level);
# desktop-only (assigned to home.pc) because kodiPackages are Linux-only
# and the IPTV PVR setup belongs to the living-room box.
{...}: {
  users.batman.home.pc = {pkgs, ...}: {
    programs.kodi = {
      enable = true;
      package = pkgs.kodi.withPackages (kodiPkgs: with kodiPkgs; [
        pvr-iptvsimple
      ]);
    };
  };
}
