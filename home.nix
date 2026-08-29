{ config, pkgs, fzf-git-sh, ... }:

{
  imports = [
    ./nvim.nix
  ];

  home.stateVersion = "26.05";
  home.sessionVariables.EDITOR = "nvim";

  home.packages = with pkgs; [
    fzf
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

systemd.user.services.borgmatic = {
  Service = {
    Environment = [
      "BORG_PASSPHRASE_FILE=%h/.borg-passphrase"
    ];
  };
};

  # backups
  programs.borgmatic = {
  enable = true;
  backups = {
    nix-home = {
      location = {
        sourceDirectories = [ "${config.home.homeDirectory}/Documents" ];
        repositories = [ "${config.home.homeDirectory}/mnt/nix-backups" ];
      };
      retention = {
        keepDaily = 7;
        keepWeekly = 4;
        };
      };
    };
  };

  services.borgmatic = {
    enable = true;
    frequency = "daily";
  };


  programs.carapace.enable = true;
  programs.carapace.enableFishIntegration = true;

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };
  xdg.configFile = {
    "fish/conf.d/fzf-git.fish".source = "${fzf-git-sh}/fzf-git.fish";
    "fish/conf.d/fzf-git.sh".source = "${fzf-git-sh}/fzf-git.sh";
  };

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set fish_greeting
    '';

    plugins = [
      { name = "fzf-fish"; src = pkgs.fishPlugins.fzf-fish; }
      { name = "autopair"; src = pkgs.fishPlugins.autopair; }
      { name = "sponge"; src = pkgs.fishPlugins.sponge; }
      { name = "done"; src = pkgs.fishPlugins.done; }
      { name = "colored-man-pages"; src = pkgs.fishPlugins.colored-man-pages; }
    ];

    shellAbbrs = {
      gco = "git checkout";
      ns = "nix shell nixpkgs#";
    };
  };

  programs.ghostty = {
    enable = true;

    settings = {
      theme = "Catppuccin Frappe";
      font-size = 12;
    };
  };

  programs.zoxide.enable = true;
  programs.starship.enable = true;
  programs.eza.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  }; 
  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };

}
