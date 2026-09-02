# AI agents

[← program notes](index.md) · module: `batman/agents.nix`

## The tool bundle

From the **llm-agents** flake input (github:numtide/llm-agents.nix, own
nixpkgs pin — which is why its tools substitute from
`cache.numtide.com`, see [nix caches](nix-caches.md)):

| Tool | What it is |
|---|---|
| **pi** | the coding-agent harness this config centers on |
| openskills | skill/package discovery for pi |
| plannotator | planning tool |
| herdr | session herd manager |
| rtk | runtime toolkit |

Plus `pkgs.bun` — pi's `npmCommand` is set to `bun`, so extension/package
installs run through bun, not npm.

All Linux-only (`mkIf isLinux`): llm-agents exports no x86_64-darwin
packages. Assigned to `home.base`, so the laptop gets the bundle too.

## What lands where

`agents.nix` writes pi's config files into `~/.pi/agent/`:

- **`settings.json`** (declarative, from `piSettings`): theme
  `catppuccin-mocha`, `defaultProvider = "zai-coding-plan"`,
  `defaultThinkingLevel = "high"`, `hideThinkingBlock`, telemetry off,
  and the extension package list — pi-resource-center, context-mode,
  pi-studio, pi-subagents, pi-mcp-adapter, obsidian-notes,
  pi-ralph-wiggum (from a git source), the model router, and more. Treat
  this list as the source of truth; pi's own runtime additions land
  outside it (and home-manager's `backupFileExtension` deals with drift
  on re-activation).
- **`model-router.json`**: budget-capped automatic model selection —
  `maxSessionBudget = 1.0`, enabled on new sessions, with zai GLM tiers:
  `glm-5.3`+high thinking for `high`, `glm-5.2`+medium for `medium`,
  `glm-5.0`+medium for `low`.
- **`fzf.json` + `skills/`**: sourced **from the dotfiles repo** (the
  `ryan-nvim` input, same tree nvf reads) — recursive copy for skills.
- **`mcp.json`**: deliberately empty (`piMcp = { }`).

## The ZAI key flow

pi's default provider (`zai-coding-plan`) authenticates with
`ZAI_API_KEY`. The chain:

1. `secrets/zai-api-key.age` — encrypted in the repo, desktop-only
   (`home.pc`, declared in `agenix.nix`);
2. activation decrypts it to `/run/user/1000/agenix/zai-api-key`
   (tmpfs);
3. fish's `interactiveShellInit` exports `ZAI_API_KEY` from that path —
   **guarded by `test -r`** so the standalone machines (no secrets) just
   skip it instead of erroring on every shell.

Net effect: on the desktop the key is available to any interactive
process; on the laptop/Mac pi runs without it (only local/offline
flows).

## Editing

Everything above is plain Nix data → change and rebuild; there is no
runtime-only state to preserve except pi's own installed packages.
The provider/auth model means a new machine is one `fish` spawn away
from working (after the [bootstrap](../bootstrap.md) key restore).
