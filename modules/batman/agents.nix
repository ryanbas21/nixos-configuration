# Agent tools for batman
{ inputs, ... }:


{
  users.batman.home.base = { lib, pkgs, ... }:
    let
      llm-agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
      nodeGyp = pkgs.writeShellScriptBin "node-gyp" ''
        exec "${pkgs.nodejs}/bin/node" \
          "${pkgs.nodejs}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js" "$@"
      '';
      # ... put nodeGyp in the makeBinPath list instead of pkgs.node-gyp
      # pi installs extensions at runtime into ~/.pi/agent/npm via bun
      # (settings.json "packages"). Native deps like node-pty fall back to
      # node-gyp when no prebuild matches, so pi needs a build chain on
      # its PATH — scoped to pi, not the user session or systemPackages.
      piWrapped = pkgs.symlinkJoin {
        name = "pi";
        paths = [ llm-agents.pi ];
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          wrapProgram $out/bin/pi --prefix PATH : ${
            pkgs.lib.makeBinPath [
              pkgs.bun # npmCommand = [ "bun" ]
              pkgs.nodejs
              pkgs.typescript-language-server # pi-lsp-tools TS LSP (loads tsconfig plugins: @effect/language-service)
              nodeGyp
              pkgs.python3
              pkgs.gnumake
              pkgs.gcc
              llm-agents.rtk
              # pi-rtk-optimizer resolves and runs `rtk rewrite` via
              # pi.exec — a direct spawn, no shell — so rtk (and the
              # `which` the resolver probes with) must be on pi's own
              # PATH in every launch context (herdr panes, desktop
              # launchers), not just login shells.
              pkgs.which
              # oh-my-pi's pi-rewind auto-checkpoint spawns `git` via
              # node child_process (posix_spawn, no shell) at every
              # turn start; without git on pi's own PATH those
              # checkpoints fail with "ENOENT: posix_spawn 'git'" in
              # the same PATH-poor launch contexts as rtk above.
              pkgs.git
            ]
          }
        '';
      };

      # Stdio proxy for typescript-language-server that injects the
      # @effect/language-service tsserver plugin into the client's
      # initialize request, resolved from the workspace node_modules
      # (the process cwd pi-lsp-tools spawns it with).
      # pi-lsp-tools cannot send initializationOptions itself, and tls
      # only loads tsserver plugins declared there — tsconfig.json
      # compilerOptions.plugins alone does not survive the tls hop.
      elsTlsShim = pkgs.writeText "els-tls-shim.mjs" ''
        import { spawn } from "node:child_process";
        import { existsSync } from "node:fs";
        import path from "node:path";

        const elsDir = path.join(process.cwd(), "node_modules", "@effect", "language-service");
        const hasEls = existsSync(path.join(elsDir, "package.json"));

        const child = spawn("typescript-language-server", ["--stdio"], {
          stdio: ["pipe", "pipe", "pipe"],
        });
        child.stdout.pipe(process.stdout);
        child.stderr.pipe(process.stderr);
        child.on("exit", (code) => process.exit(code ?? 1));

        let pending = Buffer.alloc(0);
        let injected = false;

        const frame = (body) => "Content-Length: " + Buffer.byteLength(body) + "\r\n\r\n" + body;

        process.stdin.on("data", (chunk) => {
          pending = Buffer.concat([pending, chunk]);
          for (;;) {
            const sep = pending.indexOf("\r\n\r\n");
            if (sep < 0) return;
            const header = pending.subarray(0, sep).toString("latin1");
            const m = header.match(/Content-Length:\s*(\d+)/i);
            if (!m) { pending = pending.subarray(sep + 4); continue; }
            const len = Number(m[1]);
            const start = sep + 4;
            if (pending.length < start + len) return;
            let body = pending.subarray(start, start + len).toString("utf8");
            pending = pending.subarray(start + len);
            if (!injected && hasEls) {
              try {
                const msg = JSON.parse(body);
                if (msg.method === "initialize") {
                  injected = true;
                  const io = msg.params?.initializationOptions ?? {};
                  io.plugins = [
                    ...(io.plugins ?? []),
                    {
                      name: "@effect/language-service",
                      location: elsDir,
                      enableForWorkspaceTypeOperation: true,
                    },
                  ];
                  msg.params = { ...(msg.params ?? {}), initializationOptions: io };
                  body = JSON.stringify(msg);
                }
              } catch { /* malformed frame: pass through untouched */ }
            }
            child.stdin.write(frame(body));
          }
        });
        process.stdin.on("end", () => child.stdin.end());
      '';
      piMcp = { };
      piModelRouter = {
        maxSessionBudget = 1.0;
        # No enableOnNewSession here: pi-model-router 0.4.4 never reads
        # that key (verified against the installed package source — it
        # was a no-op all along). Sessions start on the router via
        # settings.json's defaultModel below; profiles register as
        # router/<profile> models.

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
              model = "zai/glm-5-turbo";
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
        # Start every session on the model-router's logical provider.
        # pi resolves the startup model as getModel(defaultProvider,
        # defaultModel) — a bare model-id lookup *inside* the named
        # provider — so the pair must be "router" + "auto": the
        # extension registers each model-router.json profile as a model
        # with id <profile> under provider "router". A defaultModel of
        # "router/auto" under another provider never resolves and pi
        # silently falls back to an arbitrary authenticated model.
        defaultProvider = "router";
        defaultModel = "auto";
        defaultThinkingLevel = "high";
        hideThinkingBlock = true;
      };

    in
    {
      # Linux-only: llm-agents exports no x86_64-darwin packages (its
      # per-system set stops at aarch64/x86_64-linux), so forcing these
      # on the Intel Mac export throws "attribute 'x86_64-darwin' missing".
      home.packages = lib.mkIf pkgs.stdenv.hostPlatform.isLinux [
        piWrapped
        pkgs.bun
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.openskills
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.plannotator
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.plannotator-tui
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.rtk
      ];

      # Release-age cooldown for the node/bun toolchain this module
      # installs: npm and bun both refuse package versions published
      # less than 7 days ago — the supply-chain blast-radius window
      # behind Pareto Security's "Package managers delay new releases"
      # check, which reads exactly these two files. Units differ: npm's
      # min-release-age is Number, hint '<days>' (npm ≥ 11.14 enforces
      # it; nixpkgs ships 11.17); bun's minimumReleaseAge is seconds,
      # hence 604800. Side effect: installing a version published
      # inside the window errors (npm ETARGET / bun "no matching
      # version") — pi's runtime extension installs included; exempt
      # names via `min-release-age-exclude` (npm) or
      # `minimumReleaseAgeExcludes` (bun) if a too-fresh release ever
      # genuinely can't wait a week.
      home.file.".npmrc".text = ''
        min-release-age=7
      '';
      home.file.".bunfig.toml".text = ''
        [install]
        # 7 days, in seconds — bun's unit
        minimumReleaseAge = 604800
      '';

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

      # herdr config sourced from the dotfiles repo, same as the pi
      # files above — one source of truth for agent tooling config.
      # herdr is in the Linux-only package list; the config is
      # unconditional like the pi files (harmless where the binary is
      # absent).
      home.file.".config/herdr/config.toml".source =
        "${inputs.ryan-nvim}/herdr/.config/herdr/config.toml";

      # Route pi-lsp-tools' typescript server through the shim above.
      # autoInstall stays enabled for the other language servers; the
      # typescript entry only overrides the command (extensions stay
      # default). Without this, pi's TS LSP runs bare tls with no
      # effect plugin.
      home.file.".pi/lsp-config.yaml".text = ''
        servers:
          typescript:
            command: [ "node", "${elsTlsShim}", "--stdio" ]
      '';


    };
}

