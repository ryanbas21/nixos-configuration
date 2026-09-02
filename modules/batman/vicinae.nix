# Vicinae (github:vicinaehq/vicinae): a Qt desktop launcher. The flake's
# home-manager module installs the package, writes settings to
# ~/.config/vicinae/nix.json, and runs the daemon as a systemd user
# service; the NixOS module adds the setcap wrapper the input server
# needs (clipboard/emoji pasting, snippets). Docs: docs.vicinae.com/nixos
{ inputs, ... }: {
  # Both the desktop and the standalone Linux export. The HM module is
  # imported unconditionally — imports must never reference module args
  # like pkgs (that recurses) — and only programs.vicinae is gated on
  # Linux, same convention as nvf.nix/ghostty.nix: the vicinae flake only
  # packages x86_64-linux, so the Intel Mac export must evaluate this as
  # disabled (self.packages.x86_64-darwin would not exist).
  users.batman.home.base = { lib, pkgs, ... }: {
    imports = [ inputs.vicinae.homeManagerModules.default ];

    # The package's menu entry runs `vicinae server --replace`, which
    # SIGKILLs the unit-owned daemon every time the icon is clicked and
    # reignites the Restart=always crash loop (happened twice already:
    # 09:22 and 10:0x). This shadows it under the same desktop ID
    # (~/.local/share/applications/vicinae.desktop beats the profile
    # copy per XDG precedence) with an IPC-only command that just opens
    # the window against whatever daemon is running. Gated with the
    # same isLinux mkIf as programs.vicinae — the entry is dead weight
    # on the darwin export.
    xdg.desktopEntries.vicinae = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      name = "Vicinae";
      exec = "vicinae open";
      icon = "vicinae";
      comment = "A focused launcher for your desktop";
      categories = [ "Utility" ];
      settings = {
        StartupWMClass = "vicinae";
        StartupNotify = "false";
      };
    };

    programs.vicinae = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      enable = true;
      # Daemon under the graphical session (default target). Set
      # systemd.environment for launcher-window env vars, e.g.
      # USE_LAYER_SHELL=1 on Wayland or QT_SCALE_FACTOR.
      systemd.enable = true;
      # settings (not set = pure in-app config) land in
      # ~/.config/vicinae/nix.json and override settings.json; tweak
      # in-app, then copy from ~/.config/vicinae/settings.json.
      # Extension config goes under settings.providers."<entrypoint-id>"
      # — get the id from the installed-extensions menu → ctrl+k →
      # "copy author and ID". Secrets never go in settings (world-
      # readable store): use programs.vicinae.settingOverrides with an
      # agenix-generated file.
      # Declarative extensions. Raycast-compat extensions build from the
      # github.com/raycast/extensions monorepo via the vicinae flake's
      # mkRayCastExtension (npm deps resolved by importNpmLock, so only
      # the repo fetch needs a hash). The rev is a pin, not a follows:
      # bump rev, fix the hashes from the build error, done.
      extensions = let
        raycastRev = "7b8979276d77b724ce032155bbc32046087efe47";
        mkRaycast = inputs.vicinae.lib.${pkgs.stdenv.hostPlatform.system}.mkRayCastExtension;
      in [
        (mkRaycast {
          name = "1password";
          rev = raycastRev;
          hash = "sha256-bUUNGNT9tGK09BUYBn9zX14qhiC7Ad0amR3ZDg0jTSk=";
        })
        (mkRaycast {
          name = "homeassistant";
          rev = raycastRev;
          hash = "sha256-NUcEcIdF86BiopYPAOYumsjv9fV9PP12WsIUTLEYDIc=";
        })
      ];
      # Native vicinae extensions (folder names from
      # github.com/vicinaehq/extensions) need the flake input
      #   vicinae-extensions.url = "github:vicinaehq/extensions";
      # then add e.g. inputs.vicinae-extensions.packages.${system}.nix
      # to the list above.
    };
  };

  # NixOS side: the input-server security wrapper. Imported here rather
  # than in nixos.modules.base so it stays a batman-machine concern; it
  # rides into the host via computers/nixos.nix's import of
  # users.batman.nixos.base. Defaults to enabled; set
  # programs.vicinae.input-server.enable = false to drop it.
  users.batman.nixos.base = {
    imports = [ inputs.vicinae.nixosModules.default ];
  };
}
