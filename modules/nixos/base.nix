# Base NixOS module for all hosts of this flake. Content formerly lived in
# ./configuration.nix; user definitions moved to modules/users.nix and the
# hardware scan import moved to the per-host module in modules/computers/.
# Help is available in the configuration.nix(5) man page and in the NixOS
# manual (accessible by running ‘nixos-help’).

{ mkModuleOption, unfreeNames, ... }: {
  options.nixos.modules.base = mkModuleOption { key = "base"; };

  config.nixos.modules.base = { config, lib, pkgs, ... }: {
    # Bootloader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

    # Configure network proxy if necessary
    # networking.proxy.default = "http://user:password@proxy:port/";
    # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

    # Enable networking
    networking.networkmanager.enable = true;

    # Set your time zone.
    time.timeZone = "America/Denver";

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";

    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };

    # Enable the X11 windowing system.
    # You can disable this if you're only using the Wayland session.
    services.xserver.enable = true;

    # Enable the KDE Plasma Desktop Environment.
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;

    # Expose the user's nix profile alongside the per-user profile so
    # nix-env installed apps (desktop entries, icons) are visible.
    environment.profiles = [
      "$HOME/.nix-profile"
      "/etc/profiles/per-user/$USER"
    ];

    # Configure keymap in X11
    services.xserver.xkb = {
      layout = "us";
      variant = "";
    };

    # Enable CUPS to print documents.
    services.printing.enable = true;

    # Enable sound with pipewire.
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # If you want to use JACK applications, uncomment this
      #jack.enable = true;

      # use the example session manager (no others are packaged yet so this is enabled by default,
      # no need to redefine it in your config for now)
      #media-session.enable = true;
    };

    # Enable touchpad support (enabled default in most desktopManager).
    # services.xserver.libinput.enable = true;
    users.defaultUserShell = pkgs.fish;

    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) unfreeNames;

    # Install firefox.
    programs.firefox.enable = true;

    # Fish
    programs.fish.enable = true;

    # List packages installed in system profile. To search, run:
    # $ nix search wget

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    # programs.mtr.enable = true;
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    # List services that you want to enable:

    # Enable the OpenSSH daemon.
    services.openssh.enable = true;

    # Pre-trust GitHub's host key in the system-wide known_hosts
    # (/etc/ssh/ssh_known_hosts — which user ssh reads as
    # GlobalKnownHostsFile), so unattended pushes (the daily
    # config-backup timer) never block on a host-key prompt. Key
    # verified against https://api.github.com/meta.
    programs.ssh.knownHosts = {
      "github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };

    # Open ports in the firewall.
    # networking.firewall.allowedTCPPorts = [ ... ];
    # networking.firewall.allowedUDPPorts = [ ... ];
    # Or disable the firewall altogether:
    # networking.firewall.enable = false;
    # Binary caches: self-hosted harmonia first, then psysonic's cachix,
    # then the canonical caches. (Nix tries every trusted key against
    # every substituter — the two lists do not need to match order.)
    nix.settings = {
      substituters = [
        "http://192.168.1.82:5000"
        "https://psysonic.cachix.org"
        "https://cache.numtide.com"
        "https://cache.nixos.org/"
      ];

      trusted-substituters = [
        "http://192.168.1.82:5000"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "psysonic.cachix.org-1:M9cQyQ7tgvUWOQ5Pyt8ozlMoPLtOZir6MfRuTH9/VYA="
        "nix-cache-1:SpVt1hjpAaEgQqnY1cIm5tjTETZbG5dQmGZ3rDbTyJc="

      ];

      experimental-features = [ "nix-command" "flakes" ];

      # Warm the home-lab harmonia cache: every path this machine BUILDS
      # (as opposed to substitutes) is pushed to the cache server's nix
      # store after the build. Harmonia 3.x serves that store over HTTP
      # (signing on the fly) but its HTTP upload route is gone, so pushes
      # go over ssh. The legacy ssh:// store is used deliberately:
      # locally-built paths are unsigned, and ssh-ng:// rejects them at
      # the remote daemon ("lacks a signature by a trusted key"), while
      # ssh:// imports via nix-store --import as root. The hook runs as
      # root and uses /root/.ssh/id_ed25519 (authorized on the server as
      # "desktop-nix-cache-push"). If the server is unreachable the hook
      # logs an error and the build itself is unaffected (|| true).
      post-build-hook = ''
        NIX_SSHOPTS="-o StrictHostKeyChecking=accept-new -o BatchMode=yes" nix copy --to ssh://root@192.168.1.82 $OUT_PATHS || true
      '';
    };
  };
}
