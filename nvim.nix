{ ryan-nvim, nvf, ... }:

{
  imports = [ nvf.homeManagerModules.nvf ];

  programs.nvf = {
    enable = true;
    defaultEditor = true;
    settings.imports = [ "${ryan-nvim}/nvf" ];
  };
}
