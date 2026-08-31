# Agent tool configs for batman (opencode + pi), symlinked from the
# ryan-nvim (dotfiles) input. Ported from ./agents.nix (top level).
{ inputs, ... }: {
  users.batman.home.base = { pkgs, ... }: {
    imports = [ inputs.pi-flake.homeManagerModules.default ];
    disabledModules = [ "programs/pi-coding-agent.nix" ];
    programs.pi-coding-agent.package = inputs.pi-flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
    programs.pi-coding-agent = {
      enable = true;

      mutableDir = true;

      # update with models
      models = { };

      extensions = [
        "npm:pi-subagents"
        "npm:pi-resource-center"
        "npm:pi-cache-optimizer"
        "npm:pi-codex-search"
        "npm:context-mode"
        "npm:@plannotator/pi-extension"
        "npm:pi-studio"
        "npm:pi-schedule-prompt"
        "npm:pi-mermaid"
        "npm:@ifi/oh-pi-themes"
        "npm:pi-fzf"
        "npm:@ayulab/oh-my-pi"
        "git:github.com/gotgenes/pi-packages"
        "npm:@yeliu84/pi-model-router"
        "npm:@pi-unipi/ralph"
        "npm:@davehardy20/pi-lsp-tools"
        "npm:@slix/obsidian-notes"
        "npm:pi-rtk-optimizer"
        "npm:pi-image-tools"
        "npm:pi-web-access"
        "npm:@quintinshaw/pi-dynamic-workflows"
        "npm:pi-powerline-footer"
        "npm:pi-subagents"
        "npm:pi-mcp-adapter"
      ];
    };
  };
}
