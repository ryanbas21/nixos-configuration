# Backups for batman. Ported from ./home.nix (top level).
# Desktop-only: assigned to home.pc, not home.base, so the standalone
# home-manager exports (modules/home.nix) never inherit the backup timers
# or the NFS-mount-dependent borgmatic config.
{ ... }:

{
  users.batman.home.pc = { config, ... }: {
    age.identityPaths = [
      "${config.home.homeDirectory}/.ssh/id_borg"
    ];

    age.secrets.borg-passphrase = {
      file = ../../secrets/borg-passphrase.age;
    };

    systemd.user.services.nixos-config-backup = {
      Unit.Description = "Backup NixOS configuration to Git";

      Service = {
        Type = "oneshot";
        ExecStart = "/etc/nixos/scripts/git-backup.sh";
      };
    };

    systemd.user.timers.nixos-config-backup = {
      Unit.Description = "Daily NixOS configuration Git backup";

      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };

      Install.WantedBy = [ "timers.target" ];
    };

    programs.borgmatic = {
      enable = true;

      backups.nix-home = {
        location = {
          sourceDirectories = [
            "${config.home.homeDirectory}"
            "/etc/nixos"
          ];

          repositories = [
            "/mnt/nix-backups"
          ];
        };

        retention = {
          keepDaily = 7;
          keepWeekly = 4;
        };
      };
    };

    services.borgmatic = {
      enable = true;
      frequency = "daily";
    };

    systemd.user.services.borgmatic = {
      Service.EnvironmentFile =
        config.age.secrets.borg-passphrase.path;
    };
  };
}

