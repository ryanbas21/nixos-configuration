# Backups for batman. Ported from ./home.nix (top level).
# Desktop-only: assigned to home.pc, not home.base, so the standalone
# home-manager exports (modules/home.nix) never inherit the backup timers
# or the NFS-mount-dependent borgmatic config.
{ ... }:

{
  users.batman.home.pc = { config, lib, ... }: {
    age.identityPaths = [
      "${config.home.homeDirectory}/.ssh/id_borg"
    ];

    # borg-passphrase itself is declared once, in agenix.nix.

    systemd.user.services.nixos-config-backup = {
      Unit.Description = "Backup NixOS configuration to Git";

      Service = {
        Type = "oneshot";
        ExecStart = "/etc/nixos/scripts/git-backup.sh";
        # Boot-race guard: the timer is Persistent=true and fires the
        # moment the machine boots; retry instead of silently losing
        # the day's push (systemd >= 254 allows Restart on Type=oneshot).
        Restart = "on-failure";
        RestartSec = "5min";
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
      Service = {
        EnvironmentFile = config.age.secrets.borg-passphrase.path;
        # The Persistent timer can fire during early boot, before the
        # NFS automount for /mnt/nix-backups is reachable; retry instead
        # of failing the whole day's backup. mkForce overrides HM's
        # stock Restart = "no".
        Restart = lib.mkForce "on-failure";
        RestartSec = "5min";
      };
    };


  };
}

