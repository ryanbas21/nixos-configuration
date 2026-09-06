{ config, ... }: {
  nixos.configurations.nixos = {
    # The underscore in ./nixos/_hardware.nix keeps import-tree from
    # auto-importing it as a flake-parts module; it is a NixOS module
    # (imports modulesPath + "/installer/scan/not-detected.nix") and is
    # imported manually here, as the host's data.
    module = {
      # Host-specific data (hostname, stateVersion, NFS
      # automounts) lives with the host, not in the shared
      # nixos.modules.base. nixpkgs.hostPlatform is NOT set here — it
      # is owned by the eval wiring (modules/nixos.nix extraModules)
      # so host modules stay importable by the VM tests.
      networking.hostName = "nixos"; # Define your hostname.

      # Self-waking ssh (client half in batman/ssh.nix): arm magic-
      # packet wake on the wired NIC (enp6s0, Realtek RTL8125B on
      # r8169). This only emits a udev .link (WakeOnLan=magic) —
      # NetworkManager keeps managing the interface. wlo1 (WiFi,
      # 192.168.1.183) is deliberately NOT armed: its MAC is randomized
      # per connection, so a magic packet cannot target it. Hardware-
      # side prerequisites this can't set: BIOS "Wake on PCI-E"/
      # onboard LAN enabled and ErP/deep-sleep OFF, else the NIC has no
      # standby power in S5 (S3 suspend wakes without ErP concerns).
      networking.interfaces.enp6s0.wakeOnLan.enable = true;

      system.stateVersion = "26.05";

      # System-level agenix identities. ntfy-url.age (this host's only
      # system secret) is encrypted to batman's id_borg — this box's
      # own host key never became a recipient (it could not be
      # ssh-keyscanned from the laptop; "nixos" does not resolve), so
      # the default host-key identityPaths left the secret
      # undecryptable here. id_borg is usable unattended at boot on
      # this host (a local /home subvolume, mounted before
      # activation), so offering it to the boot-time decrypt works.
      # Trade: on a fresh install the secret no-ops (journal note,
      # never a failed alerting unit) until the runbook restores
      # id_borg — the same first-boot property every user-level secret
      # already has. The host key stays in the list so making it a
      # recipient later needs no second change. (harmonia.nix sets its
      # identityPaths explicitly the same way.)
      age.identityPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/home/batman/.ssh/id_borg"
      ];

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

      fileSystems."/mnt/nix-backups" = {
        device = "192.168.1.30:/volume1/Backups/nix";
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
        ./nixos/_hardware.nix
        config.nixos.modules.base
        config.users.batman.nixos.base
      ];
    };
  };
}
