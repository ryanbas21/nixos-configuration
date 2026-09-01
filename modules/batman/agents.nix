# Agent tools for batman
{ inputs, ... }:

{
  users.batman.home.base = { pkgs, ... }:
    let
      piMcp = { };
      piModelRouter = {
        maxSessionBudget = 1.0;
        enableOnNewSession = true;

        profiles = {
          auto = {
            high = {
              model = "zai/glm-5.3";
              thinking = "high";
            };

            medium = {
              model = "zai/glm-5.2";
              thinking = "medium";
            };

            low = {
              model = "zai/glm-5.0";
              thinking = "medium";
            };
          };
        };
      };
      piSettings = {
        npmCommand = [ "bun" ];

        packages = [
          "npm:pi-resource-center"
          "npm:pi-cache-optimizer"
          "npm:pi-codex-search"
          "npm:context-mode"
          "npm:@plannotator/pi-extension"
          "npm:pi-studio"
          "npm:pi-schedule-prompt"
          "npm:@ifi/oh-pi-themes"
          "npm:pi-fzf"
          "npm:@ayulab/oh-my-pi"
          "git:github.com/gotgenes/pi-packages"
          "npm:@yeliu84/pi-model-router"
          {
            source = "npm:@ryan_nookpi/pi-extension-headroom";
            url = "127.0.0.1:6767";
          }
          "npm:@davehardy20/pi-lsp-tools"
          "npm:@slix/obsidian-notes"
          {
            source = "git:github.com/tmustier/pi-extensions";
            extensions = [
              "pi-ralph-wiggum/index.ts"
            ];
            skills = [
              "pi-ralph-wiggum/SKILL.md"
            ];
          }
          "npm:pi-rtk-optimizer"
          "npm:pi-image-tools"
          "npm:pi-web-access"
          "npm:@quintinshaw/pi-dynamic-workflows"
          "npm:pi-powerline-footer"
          "npm:pi-subagents"
          "npm:pi-mcp-adapter"
        ];

        enableInstallTelemetry = false;
        theme = "catppuccin-mocha";
        defaultProvider = "zai-coding-plan";
        defaultThinkingLevel = "high";
        hideThinkingBlock = true;
      };

    in
    {
      home.packages = [
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi
        pkgs.bun
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.openskills
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.plannotator
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.rtk
      ];

      home.file.".pi/agent/settings.json".text =
        builtins.toJSON piSettings;
      home.file.".pi/agent/model-router.json".text =
        builtins.toJSON piModelRouter;
      home.file.".pi/agent/fzf.json".source =
        "${inputs.ryan-nvim}/pi/.pi/agent/fzf.json";

      home.file.".pi/agent/skills" = {
        source = "${inputs.ryan-nvim}/pi/.pi/agent/skills/";
        recursive = true;
      };
      home.file.".pi/agent/mcp.json".text =
        builtins.toJSON piMcp;


    };
}

