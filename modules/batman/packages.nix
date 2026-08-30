# Packages and CLI tools for batman. Ported from ./home.nix (top level).
{...}: {
  users.batman.home.base = {config, pkgs, ...}: {
    home.packages = with pkgs; [
      fd
      bat
      kdePackages.kate
      discord
      ripgrep
      gnumake
      gcc
      git
      ghostty
      pkgs.sshfs
    ];

    programs.ghostty = {
      enable = true;

      settings = {
        theme = "Catppuccin Frappe";
        font-size = 12;
      };
    };

    programs.gh = {
      enable = true;
      settings.git_protocol = "ssh";
    };
  };
}
