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
    module = { config, lib, pkgs, ... }: {
      # Host-specific data.
      networking.hostName = "harmonia";
      nixpkgs.hostPlatform = "x86_64-linux";

      # Verified 2026-09-04 against the live box (root@192.168.1.82,
      # /etc/nixos/configuration.nix on `nix-cache`): installed at
      # 26.05. Never change it afterwards.
      system.stateVersion = "26.05";

      imports = [
        ./harmonia/_hardware.nix
        inputs.agenix.nixosModules.default
      ];

      # --- minimal headless base (instead of nixos.modules.base) ---
      # NOTE(adoption): the hand-configured box runs PermitRootLogin
      # "yes" + PasswordAuthentication true. Module defaults are
      # stricter (prohibit-password, no passwords) — from the first
      # switch root login is key-only, which makes populating
      # authorized_keys below a hard prerequisite: password recovery
      # stops working at that same moment.
      services.openssh.enable = true;
      # Local time for logs and the weekly GC timer; base sets this but
      # is skipped here, so carry it explicitly. Parity with the
      # hand-configured box (America/Denver).
      time.timeZone = "America/Denver";
      # Compressed RAM swap as an OOM cushion — same rationale as
      # hardware.nix for the desktop, restated here because this host
      # skips nixos.modules.base (would move with it if a server tier
      # ever gets promoted, per the header comment).
      zramSwap.enable = true;
      # harmonia itself. Both listeners are LAN-only concerns — the
      # desktop's substituter hits 192.168.1.82:5000 and deploys arrive
      # over ssh from the same subnet — so instead of the module-default
      # global opens (sshd's openFirewall, blanket allowedTCPPorts) the
      # ports are scoped to the home subnet via extraInputRules: the box
      # stays dark on any other network, which matters given the signing
      # key it holds. IPv6 stays default-dropped (everything addresses
      # this box by its v4 literal). extraInputRules needs the nftables
      # backend, which cannot be inherited from nixos.modules.base
      # (deliberately not imported here), so it is set in place.
      services.openssh.openFirewall = false;
      networking.nftables.enable = true;
      networking.firewall.extraInputRules = ''
        ip saddr 192.168.1.0/24 tcp dport { 22, 5000 } accept
      '';
      # Flakes for local nix ops on the box; remote rebuilds arrive as
      # ready closures from the desktop and don't even need this.
      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      # Parity with the box's hand-rolled package list — a console-only
      # rescue/debug kit for incidents (the cache path itself needs
      # none of these; harmonia's store is served, not built, there).
      environment.systemPackages = with pkgs; [ git curl wget htop vim ];

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
      # Adopted 2026-09-04 from the box's live ~/.ssh/authorized_keys,
      # which contained exactly this one key (desktop-nix-cache-push);
      # nothing else to preserve. This assignment REPLACES the file on
      # every switch — new keys get added HERE, never on the box. As
      # adopted, the desktop is the only key-holder: if it dies,
      # cache-server root access is VM-console-only until a personal
      # admin key is added to this list.
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIlMK7jt86TlHnzvths3bWymyEZfmfxJcUQ1PkuJ/HEJ desktop-nix-cache-push"
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
