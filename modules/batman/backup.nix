# Backups for batman. Ported from ./home.nix (top level).
# Desktop-only: assigned to home.pc, not home.base, so the standalone
# home-manager exports (modules/home.nix) never inherit the backup timers
# or the NFS-mount-dependent borgmatic config.
{...}: {
  users.batman.home.pc = {config, ...}: let
    # Where the desktop's checkout of this repo lives (see README,
    # Machines). The backup timer operates on this checkout; moving the
    # checkout means changing this binding.
    repoPath = "/etc/nixos";
  in {
    systemd.user.services.nixos-config-backup = {
      Unit = {
        Description = "Backup NixOS configuration to Git";
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${repoPath}/scripts/git-backup.sh";
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
        EnvironmentFile = "%h/.borg-passphrase.env";
      };
    };

    # backups
    programs.borgmatic = {
      enable = true;
      backups = {
        nix-home = {
          location = {
            sourceDirectories = [
              "${config.home.homeDirectory}/"
              "/var/lib"
            ];
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
  };
}
