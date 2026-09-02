# Neovim (nvf)

[← program notes](index.md) · modules: `batman/nvf.nix`, `batman/_nvf/default.nix`

## What and why

Neovim is built by **nvf** (github:NotAShelf/nvf, pinned `v26.07`), a
Nix-native neovim "distribution": it turns a Nix module tree into a
wrapped neovim with plugins, LSP servers, treesitter grammars, and lua
config all provided by the Nix store. The user's existing lua config is
**not** rewritten — it is sourced from the dotfiles repo
(github:ryanbas21/dotfiles, pinned here as the `ryan-nvim` flake input)
and merged into the nvf wrapper. Mason and lazy.nvim, the old runtime
package managers, are retired: tool binaries come from Nix
(`vim.extraPackages`) and lazy-loading is nvf's lz.n loader.

The migration was deliberately conservative: triggers, setup opts, and
keymaps were ported verbatim from the old `lua/plugins/*.lua` specs, and
the only edits to existing lua files are the two mason-path fixes in
`lsp/eslint.lua` and `lsp/elixirls.lua` (bare command names now resolved
from PATH).

Runs under `NVIM_APPNAME=nvf`, so there is no stdpath collision with any
hand-managed nvim.

## The wiring (nvf.nix)

`modules/batman/nvf.nix` enables nvf as a home-manager program and
imports `./_nvf/default.nix` as its settings module. The nvf home-manager
module is imported unconditionally but the program assignment is wrapped
in `mkIf stdenv.isLinux` — nvf's tool bundle has no `x86_64-darwin` story
(clojure-lsp is the hard blocker), so the Mac export carries the module
with nvf disabled and the Linux machines are unaffected. Note the
convention: **imports must never reference module args like `pkgs`**
(that recurses) — only the `programs.nvf` assignment is gated.

The subtlety is the `_module.args` dance: nvf's `settings` submodule runs
its own module system, and modules imported via `settings.imports`
receive only nvf's own module arguments — arguments from the outer
home-manager evaluation do not flow through. Because the settings need
the dotfiles tree, `_nvf/default.nix` declares `ryan-nvim` in its
function header and `nvf.nix` injects it:

```nix
programs.nvf.settings._module.args.ryan-nvim = inputs.ryan-nvim;
```

`modules/batman/_nvf/default.nix` (underscore: not auto-imported;
imported only by `nvf.nix`) is the full settings module:

- 27 LSP servers via `vim.lsp.enable` (nixd included);
- treesitter with `allGrammars`;
- the former lazy.nvim plugin list ported to nvf's lz.n loader
  (`vim.lazy.plugins`), triggers and configs carried over;
- tool binaries provided by Nix via `vim.extraPackages`;
- lua sourced from `"${ryan-nvim}/nvim/.config/nvim"`: the tree is
  prepended to the runtimepath (so its `lsp/*.lua` win) and
  `options.lua`, `mappings.lua`, `autocmds.lua` load at startup
  (`init.lua` itself is **not** sourced — it bootstraps lazy.nvim and
  prepends mason to PATH, both retired);
- `vendoredKeymaps.enable = false` — the user's `mappings.lua` owns all
  keybindings.

## Things worth remembering

- **LSP server list is duplicated by hand.** `handlers.lua` (in
  dotfiles) used to discover `lsp/*.lua` via `stdpath("config")`, which
  does not exist under `NVIM_APPNAME=nvf` — so `_nvf/default.nix` lists
  the servers explicitly in `lspServers` and calls `vim.lsp.enable()`
  with them after sourcing `handlers.lua`. **Adding a new LSP server
  means: lua file in dotfiles + entry in `lspServers` + binary in
  `vim.extraPackages`.**
- **Pinned plugins.** Three plugins missing from nixpkgs
  (`schemastore-nvim`, `vim-rescript`, `ts-error-translator-nvim`) are
  built from the commits pinned in the old `lazy-lock.json`, with hashes
  — bumping means editing rev + hash.
- **Dependency-edge stripping.** Several nixpkgs vimPlugins declare
  dependencies (haskell-snippets→luasnip, every neotest adapter→neotest,
  blink-emoji→blink.cmp) that mnw would force-load into `/start`,
  duplicating the lazy `/opt` registration. Those edges are stripped via
  `overrideAttrs` with `doCheck = false` (the require-check would run
  without the dependency on the *test* runtime path and fail the build,
  even though real runtime always loads the dependency first). Do not
  "simplify" these away — the duplicate-install warning comes back.
- **Theme duality:** nvf's theme module sets catppuccin-mocha, but
  onedarkpro is loaded eagerly with priority 999 and runs
  `colorscheme onedark` at startup, so onedark wins at runtime — same as
  the old setup.
- **Tool gaps (not in nixpkgs, left PATH-resolved):** `mcp-hub`,
  `purescript-language-server`, `purs-tidy`, `jsonlint`, `sonarlint`.
  The `mcphub-nvim` plugin is cmd-gated, so it only fails if actually
  opened.
- **format_on_save** skips `package.json` on purpose (LSP formatters can
  restore deleted dependencies due to stale document state).

## Updating

nvf follows the root nixpkgs input; bumping nvf means `nix flake update
nvf` (plus nixpkgs/home-manager together per the
[operations ritual](../operations.md)). The dotfiles lua moves
independently via the `ryan-nvim` input.
