# NixOS configuration

System configuration for the NixOS laptop: one host (`nixos`) and one user
(`batman`), built with NixOS + home-manager on flake-parts. The repo is
organized as one feature per file: dropping a `.nix` file into `modules/` is
the only step needed to enable it. Neovim is built by nvf, with its lua
sourced from the dotfiles repo through the `ryan-nvim` flake input.

The structure follows the [dendritic pattern](https://github.com/mightyiam/dendritic);
[mightyiam/infra](https://github.com/mightyiam/infra) is the canonical
implementation.

## The big picture

Two configuration repos, one per machine:

- **github:ryanbas21/dotfiles** — the CachyOS desktop. A plain GNU Stow repo
  (zsh, lazy.nvim neovim, i3/xmonad, ...). It contains no Nix code; its
  `nvim/.config/nvim` lua tree survives there as data.
- **github:ryanbas21/nixos-configuration** — this repo, the only Nix repo:
  the NixOS laptop's system plus batman's home-manager (fish shell bundle,
  nvf-managed neovim, backups).

The bridge between them:

```
github:ryanbas21/dotfiles        (CachyOS desktop; GNU Stow; no Nix)
        |
        | pinned as flake input `ryan-nvim`
        | (the nvim lua tree, consumed as data)
        v
github:ryanbas21/nixos-configuration   (this repo; the NixOS laptop)
        system config + batman's home-manager (fish, nvf neovim, backups)
```

## How a host is assembled

Read the repo in this order. Three terms, one sentence each:

- **mkFlake (flake-parts)**: the entire flake output set is produced by one
  big module evaluation, and every file under `modules/` is a module of that
  evaluation.
- **import-tree**: a helper that recursively imports every `.nix` file under
  a directory, except files or directories whose path contains `/_` — those
  are manual-import only.
- **deferredModule**: a NixOS/home-manager module stored as an option's value
  instead of being imported now; it is merged and evaluated later, when the
  machinery feeds it into the real evaluation.

1. `flake.nix` declares the inputs and nothing else, then hands off with
   `outputs = inputs: import ./outputs.nix inputs`.
2. `outputs.nix` runs `flake-parts.lib.mkFlake { inherit inputs; }`, imports
   the whole `modules/` tree via import-tree, and sets
   `systems = ["x86_64-linux"]`. From here on, "a file under `modules/`" and
   "an imported module" mean the same thing.
3. Feature files never import each other; they only assign to option
   namespaces:

   | Namespace | Holds |
   |---|---|
   | `nixos.configurations.<name>` | per-host data, one submodule per host |
   | `nixos.modules.base` | the shared system-level module, merged into every host |
   | `homeManager.modules.base` | the shared home-manager module |
   | `users.<name>.nixos.base` | the NixOS-side module for a user |
   | `users.<name>.home.base` | the home-manager-side module for a user |

4. `modules/nixos.nix` is machinery: each `nixos.configurations.<name>`
   wraps nixpkgs' `eval-config.nix` and exports, per host:
   - `flake.nixosConfigurations.<name>` — the full evaluation result;
   - `flake.nixosModules.host` — the raw `nixos` host module; this is what
     the machine-local wrapper flake composes with the hardware file;
   - `flake.checks."x86_64-linux"."configurations:nixos:nixos"` — the host
     toplevel, so `nix flake check` builds the whole system.
5. `modules/users.nix` wires a user together: the static part of
   `users.batman.nixos.base` declares the batman account (normal user,
   `wheel` + `networkmanager`) and sets
   `home-manager.users.batman = users.batman.home.base`, so everything the
   batman feature files assign to `users.batman.home.base` lands inside
   home-manager.
6. `modules/home-manager.nix` adds home-manager's NixOS module to
   `nixos.modules.base` (with `useGlobalPkgs` and `useUserPackages`) and sets
   `sharedModules` to `homeManager.modules.base` plus a small module syncing
   `home.stateVersion` from `osConfig.system.stateVersion`.
7. `modules/computers/nixos.nix` is the host itself, as data:
   `system.stateVersion = "26.05"`, plain
   `nixpkgs.hostPlatform = "x86_64-linux"`,
   `imports = [ config.nixos.modules.base config.users.batman.nixos.base ]`,
   and an `mkDefault` stand-in root filesystem (explained under
   [Hardware & deployment](#hardware--deployment)).

## File tour

```
.
├── flake.nix                    inputs only; delegates to outputs.nix
├── outputs.nix                  mkFlake + import-tree of ./modules
├── flake.lock                   locked input revisions
├── LICENSE                      public domain
├── .gitignore                   result/, .direnv, hardware-configuration.nix
├── modules/
│   ├── lib.nix                  mkModuleOption helper
│   ├── eval-modules.nix         generic "wrap any eval-config" machinery
│   ├── nixos.nix                host option tree; nixosConfigurations /
│   │                            nixosModules.host / checks exports
│   ├── home-manager.nix         homeManager.modules.base; wires HM into NixOS
│   ├── users.nix                users.<name>.* slots; declares batman
│   ├── computers/
│   │   └── nixos.nix            the host, as data
│   ├── nixos/
│   │   ├── base.nix             system-level base (ex-configuration.nix)
│   │   └── flake-source.nix     nixpkgs.flake.source + version metadata
│   └── batman/
│       ├── fish.nix             fish + shell UX
│       ├── nvf.nix              nvf wiring (+ ryan-nvim injection)
│       ├── packages.nix         home.packages, ghostty, gh
│       ├── backup.nix           borgmatic + git backup timer
│       └── _nvf/
│           └── default.nix      nvf settings module (manual import)
└── scripts/
    ├── git-backup.sh            the script the backup timer runs
    └── etc-nixos/
        └── flake.nix            COPY-ME wrapper template for /etc/nixos
```

Notes on the files that are not self-explanatory:

- `modules/lib.nix`: `mkModuleOption`, the helper behind every module slot
  (delivered to all modules via `_module.args.mkModuleOption`). It types the
  option as `deferredModuleWith` (merging optional `static` modules); its
  `apply` wraps the result with a `key` so merge errors point at the right
  slot.
- `modules/eval-modules.nix`: a reusable option set (`fn`, `module`, `args`,
  `configuration`) that calls any eval-config-style function with the
  accumulated module; `modules/nixos.nix` instantiates it with
  `import "${inputs.nixpkgs}/nixos/lib/eval-config.nix"`.
- `modules/nixos/flake-source.nix`: restores what
  `nixpkgs.lib.nixosSystem` injects but plain eval-config loses:
  `nixpkgs.flake.source = mkDefault inputs.nixpkgs.outPath` (keeps
  `<nixpkgs>`/registry resolution working — the fish abbreviation
  `ns = "nix shell nixpkgs#"` depends on it) plus revision-aware
  `system.nixos` version metadata.
- `modules/nixos/base.nix`: systemd-boot, Plasma 6 + SDDM, pipewire,
  NetworkManager, fish as `users.defaultUserShell`, gnupg agent, sshd, the
  NFS automount at `/home/batman/mnt/nix-backups`, Firefox, CUPS, unfree
  packages, and the `nix-command`/`flakes` experimental features.
- `modules/batman/fish.nix`: fish (cleared greeting; fzf-fish, autopair,
  sponge, done, colored-man-pages plugins; `gco` and `ns` abbreviations)
  plus fzf, starship, zoxide, carapace, eza, direnv + nix-direnv, and
  fzf-git.sh keybindings closed over from `inputs.fzf-git-sh`.
- `modules/batman/packages.nix`: `home.packages` (fd, bat, ripgrep, git,
  gcc, gnumake, sshfs, ghostty, discord, kate) plus ghostty (Catppuccin
  Frappe) and gh (ssh protocol).
- `modules/batman/backup.nix`: daily borgmatic run (Documents to the NFS
  backup mount; 7 daily / 4 weekly retention) and a daily systemd user timer
  running `scripts/git-backup.sh`, which commits and pushes the local repo
  clone only when something changed.

## The neovim bridge (nvf + dotfiles lua)

`modules/batman/nvf.nix` enables nvf as a home-manager program and imports
`./_nvf/default.nix` as its settings module. The subtlety is the
`_module.args` dance: nvf's `settings` submodule runs its own module system,
and modules imported via `settings.imports` receive only nvf's own module
arguments — arguments from the outer home-manager evaluation do not flow
through. Because the settings need the dotfiles tree, `_nvf/default.nix`
declares `ryan-nvim` in its function header and `nvf.nix` injects it:

```nix
programs.nvf.settings._module.args.ryan-nvim = inputs.ryan-nvim;
```

`modules/batman/_nvf/default.nix` (underscore: not auto-imported; imported
only by `nvf.nix`) is the full settings module, a direct descendant of the
original dotfiles nvf configuration:

- 27 LSP servers via `vim.lsp.enable` (nixd included); treesitter with
  `allGrammars`;
- the former lazy.nvim plugin list ported to nvf's lz.n loader
  (`vim.lazy.plugins`), triggers and configs carried over;
- tool binaries provided by Nix via `vim.extraPackages` (mason retired);
- lua sourced from `"${ryan-nvim}/nvim/.config/nvim"`: the tree is
  prepended to the runtimepath (so its `lsp/*.lua` win) and
  `options.lua`, `mappings.lua`, `autocmds.lua` load at startup;
- runs under `NVIM_APPNAME=nvf`, so no stdpath collision.

## Rules of the pattern

- **Drop a file to enable it.** Any `.nix` file anywhere under `modules/` is
  imported automatically; deleting it removes the feature. There are no
  `imports = [ ./foo.nix ];` lists between feature files.
- **`/_` means manual.** Any file or directory whose path contains `/_` is
  skipped by import-tree; `modules/batman/_nvf/` is the only example.
- **One feature per file, freely named.** Paths carry no structural meaning;
  `modules/batman/` grouping is convention, not mechanism.
- **No `specialArgs` / `extraSpecialArgs`.** Feature files close over the
  `inputs` they need when assigning modules (`fish.nix` over
  `inputs.fzf-git-sh`; `nvf.nix` over `inputs.nvf` and `inputs.ryan-nvim`),
  so nothing is threaded through the NixOS/home-manager evaluations.
- **Lower-level modules are data.** NixOS/home-manager modules live in
  option values typed `deferredModule` (via `mkModuleOption`); the machinery
  files feed them to the real evaluations.

## Inputs

| Input | Provides |
|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-unstable`; the single package set for system and home |
| `home-manager` | user environments; follows `nixpkgs` |
| `nvf` | the neovim distribution, `github:NotAShelf/nvf/v26.07`; follows `nixpkgs` |
| `ryan-nvim` | `github:ryanbas21/dotfiles`, `flake = false`; the pinned lua tree nvf sources |
| `fzf-git-sh` | `github:junegunn/fzf-git.sh`, `flake = false`; fish keybindings |
| `flake-parts` | `mkFlake`, the module system everything runs on |
| `import-tree` | `github:vic/import-tree`, `flake = false`; the auto-importer |

## Hardware & deployment

**Why no hardware file lives here.** `hardware-configuration.nix` is
machine-local data, and flake evaluation only sees git-tracked files — a
gitignored hardware file inside a clone can never be used via
`nixos-rebuild --flake .`. (The repo once tracked one; it was removed and
gitignored, and each box now composes its own.) The laptop therefore builds
from `/etc/nixos`, a path flake — path flakes see all files, tracked or not —
whose entire module list is:

```nix
modules = [
  nixcfg.nixosModules.host
  ./hardware-configuration.nix
];
```

`nixcfg` is this repo, and `nixpkgs.follows = "nixcfg/nixpkgs"` keeps the
wrapper on the repo's pin. The wrapper needs no other inputs: home-manager,
nvf, ryan-nvim, and fzf-git-sh are all closed over inside this repo's
modules.

**First-time setup on the machine** (template: `scripts/etc-nixos/flake.nix`):

```sh
sudo cp scripts/etc-nixos/flake.nix /etc/nixos/flake.nix
# ensure /etc/nixos/hardware-configuration.nix is this laptop's real
# install-time file, created by nixos-generate-config
sudo nixos-rebuild switch --flake /etc/nixos
```

**Routine updates:**

```sh
cd /etc/nixos && sudo nix flake update nixcfg
sudo nixos-rebuild switch --flake /etc/nixos
```

**Validation from anywhere, no hardware needed:** `nix flake check` builds
the host toplevel. It passes because `modules/computers/nixos.nix` carries
an `mkDefault` stand-in root filesystem — a filesystem-less eval fails the
"fileSystems does not specify your root file system" assertion — while the
machine's real hardware file defines `/` at plain priority, overriding every
field of the stand-in.

## Adding a second host someday

Drop `modules/computers/<name>.nix` assigning
`nixos.configurations.<name>.module` (stateVersion, hostPlatform,
`imports = [ config.nixos.modules.base ... ]`); `nixosConfigurations.<name>`
and a flake check appear automatically. One caveat: `flake.nixosModules.host`
in `modules/nixos.nix` is currently bound to the `nixos` host specifically,
so a second machine needs its own export before the `/etc/nixos` wrapper
trick works for it.
