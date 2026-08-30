# nvf (Neovim) for batman. Ported from ./nvim.nix (top level); ryan-nvim is
# closed over from the flake inputs.
{inputs, ...}: {
  users.batman.home.base = {
    imports = [inputs.nvf.homeManagerModules.nvf];

    programs.nvf = {
      enable = true;
      defaultEditor = true;
      settings = {
        # nvf's settings.imports modules don't receive module args from the
        # outer eval, so ryan-nvim must be injected into the settings module
        # system.
        _module.args.ryan-nvim = inputs.ryan-nvim;
        imports = [./_nvf/default.nix];
      };
    };
  };
}
