# Packages and CLI tools for batman. Ported from ./home.nix (top level).
{ inputs, ... }: {
  users.batman.home.base = { lib, pkgs, ... }: {

    # Two chunks: everything, plus one Linux-only block (no x86_64-darwin
    # builds, or deliberately Mac-excluded — per-package reasons live in
    # docs/programs/shell-and-cli.md). The 1Password GUI is system-level
    # — modules/onepassword.nix — and the desktop's op is the setgid
    # onepassword-cli wrapper from the same module; /run/wrappers/bin
    # precedes profiles in PATH, so the CLI package here only actually
    # serves the standalone Linux laptop.
    home.packages = lib.mkMerge [
      (with pkgs; [ fd bat xclip cachix ripgrep ])

      # Linux-only
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux [
        inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.psysonic.packages.${pkgs.stdenv.hostPlatform.system}.psysonic
        inputs.rigup.packages.${pkgs.stdenv.hostPlatform.system}.rigup

        # Add temperature monitoring
        pkgs.lm_sensors
        pkgs.btop

        #messaging
        pkgs.signal-desktop
        pkgs.discord

        pkgs._1password-cli

        #utils
        pkgs.gnumake
        pkgs.gcc
        pkgs.git
        pkgs.ghostty
        pkgs.sshfs
      ])
    ];
  };
}
