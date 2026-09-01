# Packages and CLI tools for batman. Ported from ./home.nix (top level).
{ inputs, ... }: {
  users.batman.home.base = { lib, pkgs, ... }: {

    # The chunks preserve the desktop's historical package order exactly:
    # fd bat kate discord ripgrep gnumake gcc git ghostty sshfs.
    home.packages = lib.mkMerge [
      (with pkgs; [ fd bat xclip _1password-cli _1password-gui ])
      # Linux-only: the agenix CLI is built by the agenix flake input,
      # which follows the root nixpkgs (unstable) — and unstable 26.11
      # dropped x86_64-darwin, so forcing this package on the Intel Mac
      # export throws. Secrets are edited on the desktop, which is also
      # the machine holding the agenix decryption identity.
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux [
        inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
      ])
      # Linux-only: kate, ghostty, and sshfs do not exist for
      # x86_64-darwin in nixpkgs, so they are kept off the Intel Mac
      # standalone export. Gated on the home-manager-side stdenv
      # (per-target pkgs).
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux (with pkgs; [ kdePackages.kate ]))
      (with pkgs; [ discord ripgrep gnumake gcc git ])
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux (with pkgs; [ ghostty sshfs ]))
      # Linux-only: psysonic publishes no darwin packages and rigup's
      # x86_64-darwin output fails against nixpkgs unstable, so both stay
      # off the Intel Mac standalone export.
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux [
        inputs.psysonic.packages.${pkgs.stdenv.hostPlatform.system}.psysonic
        inputs.rigup.packages.${pkgs.stdenv.hostPlatform.system}.rigup
      ])
    ];
  };
}
