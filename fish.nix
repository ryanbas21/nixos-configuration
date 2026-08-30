# Fish + shell UX for this host (batman). Single nix repo: previously
# shared with the dotfiles flake, which no longer carries nix config.
{
  pkgs,
  fzf-git-sh,
  ...
}: {
  # The fzf-fish plugin requires fd at runtime; this keeps the module
  # self-contained on machines where fd isn't otherwise installed.
  home.packages = [pkgs.fd];

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set fish_greeting
    '';

    plugins = [
      {name = "fzf-fish"; src = pkgs.fishPlugins.fzf-fish;}
      {name = "autopair"; src = pkgs.fishPlugins.autopair;}
      {name = "sponge"; src = pkgs.fishPlugins.sponge;}
      {name = "done"; src = pkgs.fishPlugins.done;}
      {name = "colored-man-pages"; src = pkgs.fishPlugins.colored-man-pages;}
    ];

    shellAbbrs = {
      gco = "git checkout";
      ns = "nix shell nixpkgs#";
    };
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };
  xdg.configFile = {
    "fish/conf.d/fzf-git.fish".source = "${fzf-git-sh}/fzf-git.fish";
    "fish/conf.d/fzf-git.sh".source = "${fzf-git-sh}/fzf-git.sh";
  };

  programs.carapace.enable = true;
  programs.carapace.enableFishIntegration = true;

  programs.zoxide.enable = true;
  programs.starship.enable = true;
  programs.eza.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
