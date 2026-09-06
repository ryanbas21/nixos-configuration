# Backups for batman. Ported from ./home.nix (top level).
# NixOS hosts only: assigned to home.pc, not home.base, so the
# standalone home-manager exports (modules/home.nix) never inherit the
# backup timers or the NFS-mount-dependent borgmatic config.
{ ... }:

{
  # The desktop's checkout location: borgmatic's source list operates
  # on this path, bound once here so moving the checkout means changing
  # exactly one line. (The automated git-backup timer that also keyed
  # off this path is gone — commits are hand-made now, gated by the
  # pre-commit hook in modules/pre-commit.nix.)
  users.batman.home.pc = { config, lib, osConfig, ... }:
    let
      repoPath = "/etc/nixos";
      # The Synology backup share's automount point (the export itself
      # is declared per host in modules/computers/<host>.nix — a host
      # that doesn't mount it simply fails-and-retries, per the Restart
      # policy below).
      backupMount = "/mnt/nix-backups";
      # This profile only ever evaluates NixOS-integrated (it rides
      # users.batman.nixos.base, never the standalone exports), so
      # osConfig is always the host config here — never null.
      hostName = osConfig.networking.hostName;
      # The desktop predates the fleet: its borg repo lives at ITS
      # own export's root and stays there (moving it would orphan its
      # history and break its dedup). Every other host mounts its own
      # dedicated export (see the host file) and gets a <hostname>
      # subdirectory repo — separate repos mean no cross-host borg
      # locking over NFS and independent retention, and because no
      # host's repo directory is ever a parent of another's, borg's
      # refusal to nest repos inside repos (2026-09-05) never trips.
      repository =
        if hostName == "nixos" then backupMount else "${backupMount}/${hostName}";
    in
  {
    age.identityPaths = [
      "${config.home.homeDirectory}/.ssh/id_borg"
    ];

    # borg-passphrase itself is declared once, in agenix.nix.

    programs.borgmatic = {
      enable = true;

      backups.nix-home = {
        location = {
          sourceDirectories = [
            "${config.home.homeDirectory}"
            repoPath
          ];

          repositories = [
            repository
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

    # NO MID-SWITCH BACKUPS: home-manager's unit switcher (sd-switch)
    # stop-starts a unit whose file content changed — and for this
    # oneshot "starting" means RUNNING a backup synchronously inside
    # the switch (the 3m ExecStartPre settle + borg over NFS; that is
    # the 2026-09-04 switch that outran its start timeout). sd-switch
    # only considers units that are active/activating at switch time
    # — a failed run waiting out its 5min Restart=on-failure delay
    # counts as activating, which is how 09-04 bit — and it reads
    # X-SwitchMethod from the NEW unit file (sd-switch 0.6.4,
    # KeepOld => leave the running unit alone). So this directive
    # makes every future edit of this unit switch-safe on every host:
    # a run in flight finishes undisturbed; the new content applies at
    # the next timer fire. An idle oneshot is never touched either
    # way. Backup *config* changes still belong in programs.borgmatic
    # above (writes the yaml, leaves this unit file untouched).
    systemd.user.services.borgmatic = {
      Unit = {
        X-SwitchMethod = "keep-old";
        # TWO failed spellings of "don't gate backups on AC power", both
        # on the framework's journal (2026-09-05/06): home-manager's
        # stock ConditionACPower=true silently skips every battery run
        # ("timer green, service skipped" — the framework's first
        # weeks), and the first fix — mkForce (hostName == "nixos"),
        # rendering ConditionACPower=false on battery hosts — INVERTED
        # it: systemd conditions are assertions to SATISFY, so false
        # means "run only on battery", and the docked laptop skipped
        # its 2026-09-06 00:07 fire instead. A condition assigned an
        # EMPTY value is how a condition is removed from a unit
        # (systemd.unit(7): conditions are list settings; empty
        # assignment resets the list) — so battery hosts get "", the
        # always-on-AC desktop keeps "true". A daily incremental is
        # minutes on battery, and the systemd-inhibit in ExecStart
        # already keeps sleep from interrupting it.
        ConditionACPower = lib.mkForce (lib.optionalString (hostName == "nixos") "true");
      };
      Service = {
        EnvironmentFile = config.age.secrets.borg-passphrase.path;
        # The Persistent timer can fire during early boot, before the
        # NFS automount for the backup share is reachable (or while a
        # laptop is off-LAN entirely); retry instead of failing the
        # whole day's backup. mkForce overrides HM's stock
        # Restart = "no".
        Restart = lib.mkForce "on-failure";
        RestartSec = "5min";
      };
    };


  };
}

