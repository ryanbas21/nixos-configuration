# Fish + shell UX for batman. Ported from ./fish.nix (top level); the
# fzf-git-sh input is closed over from the flake inputs.
{ inputs, ... }: {
  users.batman.home.base = { pkgs, ... }: {
    # The fzf-fish plugin requires fd at runtime; this keeps the module
    # self-contained on machines where fd isn't otherwise installed.
    home.packages = [ pkgs.fd ];
    home.sessionVariables = { };

    programs.fish = {
      enable = true;

      interactiveShellInit = ''
        set fish_greeting
        set -gx OP_BIOMETRIC_UNLOCK true
        set -gx DEFAULT_USER $(whoami)
        set -gx ZAI_API_KEY (cat /run/user/1000/agenix/zai-api-key)
      '';

      plugins = [
        { name = "fzf-fish"; src = pkgs.fishPlugins.fzf-fish; }
        { name = "autopair"; src = pkgs.fishPlugins.autopair; }
        { name = "sponge"; src = pkgs.fishPlugins.sponge; }
        { name = "done"; src = pkgs.fishPlugins.done; }
        { name = "colored-man-pages"; src = pkgs.fishPlugins.colored-man-pages; }
      ];

      shellAbbrs = {
        gco = "git checkout";
        ns = "nix shell nixpkgs#";
      };
    };

    xdg.configFile = {
      "fish/conf.d/fzf-git.fish".source = "${inputs.fzf-git-sh}/fzf-git.fish";
      "fish/conf.d/fzf-git.sh".source = "${inputs.fzf-git-sh}/fzf-git.sh";
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
  };
}
