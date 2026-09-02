# The harmonia cache server (192.168.1.82 on the LAN): the binary cache
# the desktop's post-build-hook warms (modules/nixos/base.nix) and the
# first substituter in its list.
#
# Headless and single-purpose, so it deliberately imports NEITHER the
# desktop-heavy nixos.modules.base (no Plasma, no home-manager, no
# backups) NOR a users.<name> slot (no batman): root is the only
# account, and the box holds no user-level secrets. This is the slim
# host variant the virtualization.nix comment describes — if a second
# server-class host appears, promote the minimal base below to
# nixos.modules.server (mkModuleOption + import from host files).
#
# Deployed from the desktop, never rebuilt on the box:
#
#   sudo nixos-rebuild switch --flake .#harmonia --target-host root@192.168.1.82
#
# nixos-rebuild builds locally (substituting from this repo's caches —
# including the cache this host serves) and copies the closure over ssh
# to the target, authenticating with root's key that is already
# authorized on .82 ("desktop-nix-cache-push", the same key the push
# hook uses). The box needs no checkout of this repo.
#
# One-time adoption runbook: docs/programs/nix-caches.md,
# "Bringing .82 under management".
{ inputs, ... }: {
  nixos.configurations.harmonia = {
    # The underscore in ./harmonia/_hardware.nix keeps import-tree from
    # auto-importing it as a flake-parts module; it is a NixOS module
    # imported manually here, as the host's data.
    module = { config, lib, ... }: {
      # Host-specific data.
      networking.hostName = "harmonia";
      nixpkgs.hostPlatform = "x86_64-linux";

      # TODO(first deploy): verify on the box (`nixos-version`, and the
      # stateVersion in its current /etc/nixos/configuration.nix) and set
      # to the release it was actually installed with. Never change it
      # afterwards.
      system.stateVersion = "26.05";

      imports = [
        ./harmonia/_hardware.nix
        inputs.agenix.nixosModules.default
      ];

      # --- minimal headless base (instead of nixos.modules.base) ---
      services.openssh.enable = true;
      # harmonia itself; sshd opens port 22 via its own module default.
      networking.firewall.allowedTCPPorts = [ 5000 ];
      # Flakes for local nix ops on the box; remote rebuilds arrive as
      # ready closures from the desktop and don't even need this.
      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      # --- the cache ---
      services.harmonia.cache = {
        enable = true;
        # The key is loaded via systemd LoadCredential= (root reads the
        # file at service start; the DynamicUser service receives a copy
        # under /run/credentials), so the agenix secret stays root-owned
        # 0400 — no ownership juggling.
        signKeyPaths = [ config.age.secrets.harmonia-signing-key.path ];
        # settings defaults apply (bind [::]:5000, priority 50) — matching
        # what the hand-configured .82 serves today.
      };
      # System-level agenix: decrypt with the host's own ssh host key,
      # so the server needs no user identity at all.
      age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      age.secrets.harmonia-signing-key.file = ../../secrets/harmonia-signing-key.age;

      # --- push access: the desktop's post-build-hook key ---
      users.users.root.openssh.authorizedKeys.keys = [
        # TODO(first deploy): on the DESKTOP run
        #   sudo cat /root/.ssh/id_ed25519.pub
        # and paste it here — that is the key already authorized on .82
        # ("desktop-nix-cache-push"). Before deploying, diff against the
        # server's current file
        #   ssh root@192.168.1.82 'cat ~/.ssh/authorized_keys'
        # and add any other admin keys to this list as well: this
        # assignment REPLACES the file on switch, and dropping the
        # deploy key would lock out remote rebuilds (console-only
        # recovery).
        #
        # This placeholder cannot silently outlive adoption: the
        # assertion below ties it to the hardware placeholder.
      ];

      # Adoption tripwire: an empty authorized_keys is not an eval error
      # by itself, so it is cross-locked against the hardware placeholder
      # — while _hardware.nix still carries the REPLACE-ME device,
      # deploys fail at activation anyway and the empty list is
      # harmless; once real hardware lands, this assertion turns a
      # still-empty list into an eval error, so `nix flake check`
      # (and CI, on every push including the timer's) catches it before
      # any deploy can lock out remote access.
      assertions = [
        {
          assertion =
            lib.hasInfix "REPLACE-ME" config.fileSystems."/".device
            || config.users.users.root.openssh.authorizedKeys.keys != [ ];
          message = "harmonia: root authorized_keys is empty — a switch would replace the server's key file and lock out remote access. Paste the desktop push key (docs/programs/nix-caches.md, adoption runbook).";
        }
      ];
    };
  };
}
