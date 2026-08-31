# nvf (Neovim) for batman. Ported from ./nvim.nix (top level); ryan-nvim is
# closed over from the flake inputs.
{inputs, ...}: {
  # Linux-only: the settings module's tool bundle includes packages with
  # no x86_64-darwin support (clojure-lsp is the hard blocker in
  # nixpkgs-26.05-darwin), and nvf/mnw target Linux first. The nvf
  # home-manager module itself is imported unconditionally — imports must
  # never reference module args like pkgs (that recurses) — and only the
  # programs.nvf assignment is gated on the home-manager-side stdenv, so
  # the NixOS desktop keeps nvf and the Intel Mac export evaluates it as
  # disabled.
  users.batman.home.base = {lib, pkgs, ...}: {
    imports = [inputs.nvf.homeManagerModules.nvf];

    programs.nvf = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      enable = true;
      defaultEditor = true;
      settings = {
        # nvf's settings.imports modules don't receive module args from
        # the outer eval, so ryan-nvim must be injected into the settings
        # module system.
        _module.args.ryan-nvim = inputs.ryan-nvim;
        imports = [./_nvf/default.nix];
      };
    };
  };
}
