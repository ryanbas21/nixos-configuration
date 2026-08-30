{ ryan-nvim, nvf, ... }:

{
  imports = [ nvf.homeManagerModules.nvf ];

  programs.nvf = {
    enable = true;
    defaultEditor = true;
    settings = {
      # nvf's settings.imports modules don't receive extraSpecialArgs, so
      # ryan-nvim must be injected into the settings module system.
      _module.args.ryan-nvim = ryan-nvim;
      imports = [ ./nvf ];
    };
  };
}
