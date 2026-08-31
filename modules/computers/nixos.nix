{config, ...}: {
  nixos.configurations.nixos = {
    # The underscore in ./nixos/_hardware.nix keeps import-tree from
    # auto-importing it as a flake-parts module; it is a NixOS module
    # (imports modulesPath + "/installer/scan/not-detected.nix") and is
    # imported manually here, as the host's data.
    module = {
      # Host-specific data (hostname, platform, stateVersion, NFS
      # automounts) lives with the host, not in the shared
      # nixos.modules.base.
      networking.hostName = "nixos"; # Define your hostname.

      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "26.05";

      # NFS automounts from the Synology NAS at 192.168.1.30, plus the
      # kernel-side nfs support they need.
      boot.supportedFilesystems = [ "nfs" ];

      fileSystems."/mnt/media" = {
        device = "192.168.1.30:/volume1/jellyfin-data/";
        fsType = "nfs4";
        options = [
          "x-systemd.automount"
          "noauto"
          "nofail"
        ];
      };

      fileSystems."/home/batman/mnt/notes" = {
        device = "192.168.1.30:/volume1/Notes";
        fsType = "nfs4";
        options = [
          "x-systemd.automount"
          "noauto"
          "nofail"
        ];
      };

      fileSystems."/home/batman/mnt/nix-backups" = {
        device = "192.168.1.30:/volume1/Backups/nix";
        fsType = "nfs";
        options = [
          "x-systemd.automount" # Mounts on demand when accessed
          "noauto"              # Skips mounting during boot so boot doesn't hang if NAS is off
          "x-systemd.idle-timeout=600" # Unmounts after 10 minutes of inactivity
          "rw"                  # Read/write access
          "user"                # Allows your user to trigger it
        ];
      };

      imports = [
        ./nixos/_hardware.nix
        config.nixos.modules.base
        config.users.batman.nixos.base
      ];
    };
  };
}
