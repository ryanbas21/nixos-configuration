# Backups for batman. Ported from ./home.nix (top level).
# Desktop-only: assigned to home.pc, not home.base, so the standalone
# home-manager exports (modules/home.nix) never inherit the backup timers
# or the NFS-mount-dependent borgmatic config.
{...}: {
  users.batman.home.pc = {config, ...}: {
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
  };
}
