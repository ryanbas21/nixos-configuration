{ ... }: {
  users.batman.home.base = { lib, pkgs, ... }: {
    programs.ghostty = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      enable = true;

      settings = {
        theme = "Catppuccin Frappe";
        font-size = 12;
      };
    };
  };
}

