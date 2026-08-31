# Packages and CLI tools for batman. Ported from ./home.nix (top level).
{...}: {
  users.batman.home.base = {lib, pkgs, ...}: {
    # The chunks preserve the desktop's historical package order exactly:
    # fd bat kate discord ripgrep gnumake gcc git ghostty sshfs.
    home.packages = lib.mkMerge [
      (with pkgs; [fd bat])
      # Linux-only: kate, ghostty, and sshfs do not exist for
      # x86_64-darwin in nixpkgs, so they are kept off the Intel Mac
      # standalone export. Gated on the home-manager-side stdenv
      # (per-target pkgs).
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux (with pkgs; [kdePackages.kate]))
      (with pkgs; [discord ripgrep gnumake gcc git])
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux (with pkgs; [ghostty sshfs]))
    ];

    programs.ghostty = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      enable = true;

      settings = {
        theme = "Catppuccin Frappe";
        font-size = 12;
      };
    };

    programs.gh = {
      enable = true;
      settings.git_protocol = "ssh";
    };
  };
}
