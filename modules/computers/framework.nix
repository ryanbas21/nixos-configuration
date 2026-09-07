{ config, inputs, ... }:

{
  nixos.configurations.framework = {
    module = {
      networking.hostName = "framework";

      system.stateVersion = "26.05";
      services.fprintd.enable = true;

      # System-level agenix identities (mirrors nixos.nix): this host's
      # own ssh host key was never made a recipient of
      # secrets/ntfy-url.age, so the module-default identityPaths left
      # /run/agenix/ntfy-url undecryptable here — every alerting path
      # (the weekly digest, OnFailure pushes, the UPS watcher) has been
      # silently dead on this box since it joined the fleet (journal
      # 2026-09-06: "notify: /run/agenix/ntfy-url missing or empty —
      # secret not decrypted?"). id_borg IS a recipient, is present,
      # and is local (the /home subvolume is mounted before
      # activation), so boot-time decrypt works unattended. The host
      # key stays in the list so making it a recipient later needs no
      # second change.
      age.identityPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/home/batman/.ssh/id_borg"
      ];

      # NFS automount from the Synology NAS at 192.168.1.30 — a
      # DEDICATED subfolder of the Backups share (nix-laptops), NOT the
      # desktop's export (Backups/nix, whose root IS the desktop's borg
      # repo): borg refuses to init a repo inside another repository's
      # tree ("A repository already exists at <parent>", 2026-09-05),
      # so each host backs up into its own export. borgmatic
      # (modules/batman/backup.nix) targets <share>/framework; a future
      # laptop would mount this same export and get <share>/<hostname>
      # beside it, never inside it. Same mount options as the desktop's
      # stanza. noauto + automount + idle-timeout keep an off-LAN
      # laptop (or a powered-off NAS) from ever blocking boot; the
      # backup service just fails and retries per its Restart policy.
      boot.supportedFilesystems = [ "nfs" ];

      fileSystems."/mnt/nix-backups" = {
        device = "192.168.1.30:/volume1/Backups/nix-laptops";
        fsType = "nfs";
        options = [
          "x-systemd.automount" # Mounts on demand when accessed
          "noauto" # Skips mounting during boot so boot doesn't hang if NAS is off
          "x-systemd.idle-timeout=600" # Unmounts after 10 minutes of inactivity
          "rw" # Read/write access
          "user" # Allows your user to trigger it
        ];
      };

      imports = [
        ./framework/_hardware.nix
        ./framework/_pam.nix
        ./framework/_mullvad.nix
        ./framework/_power.nix
        ./framework/_ups.nix
        # Secure Boot: the upstream module declares the
        # boot.lanzaboote options; this host's policy and the metal
        # runbook live in _secure-boot.nix (its header).
        inputs.lanzaboote.nixosModules.lanzaboote
        ./framework/_secure-boot.nix
        config.nixos.modules.base
        config.users.batman.nixos.base
      ];
    };
  };
}
