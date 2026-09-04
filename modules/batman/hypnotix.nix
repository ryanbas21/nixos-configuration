# Hypnotix IPTV player for batman. Desktop-only (assigned to home.pc,
# like kodi.nix/obsidian.nix) so it never reaches the standalone
# home-manager exports. The embedded libmpv renders into an X11 window
# (no Wayland surface), so under Hyprland the app must run via XWayland:
# the symlinkJoin wrapper forces GDK_BACKEND=x11 and dconf carries the
# two mpv options the upstream README recommends for the same reason
# (hypnotix parses "mpv-options" as space-separated key=value pairs).
{...}: {
  users.batman.home.pc = {pkgs, config, ...}: let
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

    # Providers as encrypted repo state: the dconf value embeds xtream
    # credentials in its serialization (name:::type:::url:::user:::pass),
    # so the whole list ships age-encrypted and is decrypted + applied
    # here, synchronously inside activation. Do NOT read the agenix
    # runtime dir (/run/user/<uid>/agenix) for this: agenix decrypts via
    # its own systemd user service (agenix.service) with no ordering
    # guarantee against home-manager activation — the runtime file was
    # missing exactly there on the first attempt (2026-09-04: "dconf
    # write: expected value" from an empty cat). rage decrypts the store
    # copy of the .age directly; id_borg is the identity secrets.nix
    # documents. Edit the list with
    # `agenix -e secrets/hypnotix-providers.age`, never in the app —
    # rebuilds re-assert it. active-provider stays app state.
    home.activation.hypnotixProviders = config.lib.dag.entryAfter [ "dconfSettings" ] ''
      providers_value=$(${pkgs.rage}/bin/rage -d -i ${config.home.homeDirectory}/.ssh/id_borg ${../../secrets/hypnotix-providers.age})
      ${pkgs.dconf}/bin/dconf write /org/x/hypnotix/providers "$providers_value"
    '';
  };

  # home-manager's dconf activation needs the dconf D-Bus service
  # (programs.dconf.enable on the NixOS side); without it the
  # mpv-options setting above fails at activation time.
  users.batman.nixos.base = {
    programs.dconf.enable = true;
  };
}
