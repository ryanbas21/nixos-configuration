# Backups for batman. Ported from ./home.nix (top level).
# Desktop-only: assigned to home.pc, not home.base, so the standalone
# home-manager exports (modules/home.nix) never inherit the backup timers
# or the NFS-mount-dependent borgmatic config.
{ ... }:

{
  # The desktop's checkout location: the git-backup timer's ExecStart and
  # the borgmatic source list both operate on this path, bound once here
  # so moving the checkout means changing exactly one line.
  users.batman.home.pc = { config, lib, ... }:
    let repoPath = "/etc/nixos";
    in
  {
    age.identityPaths = [
      "${config.home.homeDirectory}/.ssh/id_borg"
    ];

    # borg-passphrase itself is declared once, in agenix.nix.

    systemd.user.services.nixos-config-backup = {
      Unit.Description = "Backup NixOS configuration to Git";

      Service = {
        Type = "oneshot";
        ExecStart = "${repoPath}/scripts/git-backup.sh";
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
            repoPath
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

    # STABILITY WARNING: any change to this unit's content makes
    # home-manager restart it during the next switch — and restarting
    # this oneshot runs a full backup synchronously inside the switch
    # (the 3m ExecStartPre settle + borg over NFS). Backup *config*
    # changes belong in programs.borgmatic above (writes the yaml,
    # leaves this unit untouched). Learned the hard way 2026-09-04.
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

