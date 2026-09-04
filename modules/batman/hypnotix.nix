# Hypnotix IPTV player for batman. Desktop-only (assigned to home.pc,
# like kodi.nix/obsidian.nix) so it never reaches the standalone
# home-manager exports. The embedded libmpv renders into an X11 window
# (no Wayland surface), so under Hyprland the app must run via XWayland:
# the symlinkJoin wrapper forces GDK_BACKEND=x11 and dconf carries the
# two mpv options the upstream README recommends for the same reason
# (hypnotix parses "mpv-options" as space-separated key=value pairs).
{...}: {
  users.batman.home.pc = {pkgs, ...}: let
    hypnotix-x11 = pkgs.symlinkJoin {
      name = "hypnotix-x11";
      paths = [pkgs.hypnotix];
      buildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/hypnotix \
          --set GDK_BACKEND x11
      '';
    };
  in {
    home.packages = [hypnotix-x11];

    dconf.settings."org/x/hypnotix" = {
      mpv-options = "hwdec=auto-safe vo=x11";
    };
  };

  # home-manager's dconf activation needs the dconf D-Bus service
  # (programs.dconf.enable on the NixOS side); without it the
  # mpv-options setting above fails at activation time.
  users.batman.nixos.base = {
    programs.dconf.enable = true;
  };
}
