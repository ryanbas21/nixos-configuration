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
      # nixpkgs.hostPlatform is deliberately NOT set here: the real
      # eval gets it from the eval wiring (modules/nixos.nix
      # extraModules), and the VM test (harmonia/vm-test.nix) imports
      # this module under the test framework's read-only pkgs, where
      # any definition collides ("set multiple times").

      # Verified 2026-09-04 against the live box (root@192.168.1.82,
      # /etc/nixos/configuration.nix on `nix-cache`): installed at
      # 26.05. Never change it afterwards.
      system.stateVersion = "26.05";

      imports = [
        ./harmonia/_hardware.nix
        ./harmonia/_remote-builder.nix
        inputs.agenix.nixosModules.default
      ];

      # --- minimal headless base (instead of nixos.modules.base) ---
      # NOTE(adoption, learned on the first switch 2026-09-04): the
      # hand-configured box ran PermitRootLogin "yes" + password auth,
      # and root-by-password was the human's access path. The switch
      # applied the module default PermitRootLogin "prohibit-password"
      # and killed that path in one step. NixOS does NOT default
      # PasswordAuthentication off (upstream default true — verified
      # on the deployed box), so it is closed explicitly here: no
      # non-root users exist anyway, making the box fully key-only.
      # Human access: batman's id_borg (authorized_keys below); ops
      # access: sudo ssh from the desktop (the push key); last resort:
      # the VM console.
      services.openssh.enable = true;
      services.openssh.settings.PasswordAuthentication = false;
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
        # settings stay at module defaults (bind [::]:5000, priority 50)
        # — deliberately NOT the hand config's virtual_nix_store/
        # real_nix_store pair: setting those activates harmonia's
        # virtual-store mode, which 404s every narinfo in the VM test
        # (2026-09-04, three hypotheses deep). Defaults were proven on
        # the deployed box itself: the first --target-host switch served
        # a signed system-toplevel narinfo immediately after.
      };
      # System-level agenix: decrypt with the host's own ssh host key,
      # so the server needs no user identity at all.
      age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      age.secrets.harmonia-signing-key.file = ../../secrets/harmonia-signing-key.age;

      # --- root access: the push key + batman's admin key ---
      # The push key was adopted verbatim 2026-09-04 from the box's
      # live authorized_keys (its only entry). batman's id_borg — the
      # same key that is the agenix identity (secrets.nix); only the
      # public half ships here — is authorized so plain
      # `ssh root@192.168.1.82` from the desktop works without sudo.
      # This assignment REPLACES the file on every switch: new keys
      # get added HERE, never on the box.
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIlMK7jt86TlHnzvths3bWymyEZfmfxJcUQ1PkuJ/HEJ desktop-nix-cache-push"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIELiz8KiOJ2x7L1J2yx3X8RZkZ3bd/uHcsUH5rzVw8Cl batman@nixos"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHfLjVoQb6UFKvs5mo4PdTBWILJksyQytl6/vjJWG01y framework-remote-build"
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
