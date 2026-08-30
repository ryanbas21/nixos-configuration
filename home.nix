{ config, pkgs, ryan-nvim, ... }:

{
  imports = [
    ./nvim.nix
    "${ryan-nvim}/home/fish.nix"
  ];

  home.stateVersion = "26.05";

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

systemd.user.services.nixos-config-backup = {
  Unit = {
    Description = "Backup NixOS configuration to Git";
  };

  Service = {
    Type = "oneshot";
    ExecStart = "/home/batman/programming/nixos/scripts/git-backup.sh";
  };
};

systemd.user.timers.nixos-config-backup = {
  Unit = {
    Description = "Daily NixOS configuration Git backup";
  };

  Timer = {
    OnCalendar = "daily";
    Persistent = true;
  };

  Install = {
    WantedBy = [ "timers.target" ];
  };
};

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

}
