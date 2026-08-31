{ pkgs, ryan-nvim, ... }:

{
  xdg.configFile."opencode".source =
    "${ryan-nvim}/opencode/.config/opencode";

  home.file.".pi".source =
    "${ryan-nvim}/pi/.pi";
}
