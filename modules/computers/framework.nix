{ config, ... }:

{
  nixos.configurations.framework = {
    module = {
      networking.hostName = "framework";

      system.stateVersion = "26.05";
      services.fprintd.enable = true;

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
        config.nixos.modules.base
        config.users.batman.nixos.base
      ];
    };
  };
}
