# Architecture

[← README](../README.md) · [Machines](machines.md) · [Operations](operations.md) · [Bootstrap](bootstrap.md)

How this flake is put together: the module machinery, the option
namespaces every feature file assigns to, and a complete file tour.

## The big picture

Two repos, four machines:

- **github:ryanbas21/dotfiles** — home of the nvim lua tree, pinned here as
  the `ryan-nvim` flake input and consumed by nvf (plus a few pi agent
  config files); its remaining GNU Stow configs turn legacy as machines
  move onto this repo.
- **github:ryanbas21/nixos-configuration** — this repo, the only Nix repo:
  the NixOS desktop's system plus batman's home-manager (fish shell bundle,
  nvf-managed neovim, backups), and the standalone home-manager exports the
  laptop and Mac pull as users `ryan`.

```
github:ryanbas21/dotfiles        (data only; the nvim lua tree)
        |
        | pinned as flake input `ryan-nvim`
        v
github:ryanbas21/nixos-configuration   (this repo; all four machines)
        ├── nixos desktop: system config + batman's home-manager
        ├── ryan-linux:     standalone home-manager for the CachyOS laptop
        ├── ryan-intel-mac: standalone home-manager for the Intel Mac
        └── harmonia:       NixOS cache server (192.168.1.82), headless
```

The model in three sentences: NixOS machines are hosts under
`modules/computers/`, each committing its own hardware scan
(`_hardware.nix`; the underscore keeps import-tree away so the host file
imports it manually). Non-NixOS machines consume the standalone
`homeConfigurations` built by `modules/home.nix` — no hardware anything,
user-space only. Both kinds eat the same feature files through
`users.<name>.home.*`, so fish and packages stay identical across the
fleet (modulo the Linux-only bits: nvf, ghostty, sshfs, messaging, and the
desktop's backup timers).

## Three terms, one sentence each

- **mkFlake (flake-parts)**: the entire flake output set is produced by one
  big module evaluation, and every file under `modules/` is a module of that
  evaluation.
- **import-tree**: a helper that recursively imports every `.nix` file under
  a directory, except files or directories whose path contains `/_` — those
  are manual-import only.
- **deferredModule**: a NixOS/home-manager module stored as an option's value
  instead of being imported now; it is merged and evaluated later, when the
  machinery feeds it into the real evaluation.

## How a host is assembled

Read the repo in this order:

1. `flake.nix` declares the inputs and nothing else, then hands off with
   `outputs = inputs: import ./outputs.nix inputs`.

1. `outputs.nix` runs `flake-parts.lib.mkFlake { inherit inputs; }`, imports
   the whole `modules/` tree via import-tree, and sets
   `systems = ["x86_64-linux"]`. From here on, "a file under `modules/`" and
   "an imported module" mean the same thing.

1. Feature files never import each other; they only assign to option
   namespaces:

   | Namespace | Holds |
   |---|---|
   | `nixos.configurations.<name>` | per-host data, one submodule per host |
   | `nixos.modules.base` | the shared system-level module, merged into every host |
   | `homeManager.modules.base` | the shared home-manager module |
   | `home.configurations.<name>` | per-machine data for the standalone home-manager exports |
   | `users.<name>.nixos.base` | the NixOS-side module for a user |
   | `users.<name>.home.base` | the home-manager-side module for a user, all machines |
   | `users.<name>.home.pc` | home.base plus desktop-only extras (backups); NixOS hosts only |

1. `modules/nixos.nix` is machinery: each `nixos.configurations.<name>`
   wraps nixpkgs' `eval-config.nix` and exports, per host:

   - `flake.nixosConfigurations.<name>` — the full evaluation result;
   - `flake.checks."x86_64-linux"."configurations:nixos:<name>"` — the host
     toplevel, so `nix flake check` builds the whole system.

1. `modules/users.nix` wires a user together: the static part of
   `users.batman.nixos.base` declares the batman account (normal user,
   `wheel` + `networkmanager`) and sets
   `home-manager.users.batman = users.batman.home.pc`, so everything the
   batman feature files assign to `users.batman.home.base` (plus the
   desktop-only `home.pc` extras) lands inside home-manager.

1. `modules/home-manager.nix` adds home-manager's NixOS module to
   `nixos.modules.base` (with `useGlobalPkgs` and `useUserPackages`) and sets
   `sharedModules` to `homeManager.modules.base` plus a small module syncing
   `home.stateVersion` from `osConfig.system.stateVersion`.

1. `modules/home.nix` is the standalone counterpart: each
   `home.configurations.<name>` wraps home-manager's
   `homeManagerConfiguration` over `homeManager.modules.base` +
   `users.batman.home.base` (never `home.pc`, and never the osConfig
   stateVersion sync — `osConfig` is null standalone) and exports
   `flake.homeConfigurations.<name>`. The Intel Mac entry builds against
   the `nixpkgs-intel-mac` input because unstable dropped `x86_64-darwin`.

1. `modules/computers/nixos.nix` is the host itself, as data:
   `system.stateVersion = "26.05"`, plain
   `nixpkgs.hostPlatform = "x86_64-linux"`, the hostname, the NFS
   automounts (media, notes, nix-backups) with
   `boot.supportedFilesystems = [ "nfs" ]`, and
   `imports = [ ./nixos/_hardware.nix config.nixos.modules.base config.users.batman.nixos.base ]`.

1. `modules/computers/harmonia.nix` is the counter-example: a headless,
   single-purpose host (the cache server) that imports neither the
   desktop base nor a user slot — its minimal base, the harmonia service,
   the signing-key secret, and root's authorized_keys all live inline in
   the host file. Deployed remotely from the desktop via
   `--target-host`, never rebuilt on the box.

## Rules of the pattern

- **Drop a file to enable it.** Any `.nix` file anywhere under `modules/` is
  imported automatically; deleting it removes the feature. There are no
  `imports = [ ./foo.nix ];` lists between feature files.
- **`/_` means manual.** Any file or directory whose path contains `/_` is
  skipped by import-tree: `modules/batman/_nvf/` (nvf settings data) and
  every host's `modules/computers/<name>/_hardware.nix`.
- **One feature per file, freely named.** Paths carry no structural meaning;
  `modules/batman/` grouping is convention, not mechanism.
- **No `specialArgs` / `extraSpecialArgs`.** Feature files close over the
  `inputs` they need when assigning modules (`fish.nix` over
  `inputs.fzf-git-sh`; `nvf.nix` over `inputs.nvf` and `inputs.ryan-nvim`),
  so nothing is threaded through the NixOS/home-manager evaluations.
- **Lower-level modules are data.** NixOS/home-manager modules live in
  option values typed `deferredModule` (via `mkModuleOption`); the machinery
  files feed them to the real evaluations.

## Shared conventions (modules/lib.nix)

`modules/lib.nix` delivers three conventions to every module via
`_module.args`:

- **`mkModuleOption`** — the helper behind every module slot. It types the
  option as `deferredModuleWith` (merging optional `static` modules); its
  `apply` wraps the result with a `key` so merge errors point at the right
  slot.
- **`unfreeNames`** — the single allowlist behind every
  `allowUnfreePredicate` in the repo (`modules/nixos/base.nix` and the
  standalone exports in `modules/home.nix`). Verified against `meta.license`
  at the locked revisions: everything else in the fleet (ghostty, kodi,
  psysonic, rigup) is free-licensed. Names are per-derivation
  (`lib.getName`), so wrapped packages list their unwrapped halves too.
- **`cachixCache`** — the single source of the personal binary cache's URL
  and public key; see [nix caches](programs/nix-caches.md).

## Inputs

| Input | Provides |
|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-unstable`; the package set for the system, the desktop's home, and `ryan-linux` |
| `nixpkgs-intel-mac` | `github:NixOS/nixpkgs/nixpkgs-26.05-darwin`; feeds only the `ryan-intel-mac` export, since unstable dropped `x86_64-darwin` |
| `agenix` | secrets: the home-manager module + `agenix` CLI; follows `nixpkgs` |
| `home-manager` | user environments; follows `nixpkgs` |
| `disko` | declarative partitioning, consumed by the disko CLI via `flake.diskoConfigurations`; follows `nixpkgs` |
| `nvf` | the neovim distribution, `github:NotAShelf/nvf/v26.07`; follows `nixpkgs` |
| `ryan-nvim` | `github:ryanbas21/dotfiles`, `flake = false`; the pinned lua tree nvf sources |
| `fzf-git-sh` | `github:junegunn/fzf-git.sh`, `flake = false`; fish keybindings |
| `psysonic` | the psysonic tool (`packages.nix`); own nixpkgs pin |
| `llm-agents` | pi, openskills, plannotator, herdr, rtk (`agents.nix`); own nixpkgs pin |
| `rigup` | the rigup tool (`packages.nix`); own nixpkgs pin |
| `flake-parts` | `mkFlake`, the module system everything runs on |
| `import-tree` | `github:vic/import-tree`, `flake = false`; the auto-importer |
| `vicinae` | the desktop launcher (`vicinae.nix`); own nixpkgs pin (deliberately no `follows` — see [nix caches](programs/nix-caches.md)) |

## Complete file tour

```
.
├── flake.nix                    inputs only; delegates to outputs.nix
├── outputs.nix                  mkFlake + import-tree of ./modules
├── flake.lock                   locked input revisions
├── LICENSE                      public domain
├── .gitignore                   result/, .direnv, test-driver history, key material
├── .github/workflows/ci.yml     CI: eval-only flake check + standalone home builds
├── modules/
│   ├── lib.nix                  mkModuleOption helper; unfree allowlist; cachixCache
│   ├── eval-modules.nix         generic "wrap any eval-config" machinery
│   ├── nixos.nix                host option tree; nixosConfigurations / checks exports
│   ├── home.nix                 standalone home option tree; homeConfigurations exports
│   ├── home-manager.nix         homeManager.modules.base; wires HM into NixOS
│   ├── users.nix                users.<name>.* slots; declares batman
│   ├── disko.nix                flake.diskoConfigurations — disk layouts
│   │                            for the disko CLI (not in any host eval)
│   ├── time.nix                 ntpd-rs time sync (timeZone static in base.nix)
│   ├── security.nix             paretosecurity posture checks (system service)
│   ├── sudo.nix                 sudo-rs replaces classic sudo
│   ├── maintenance.nix          GC + store optimisation + boot-entry caps
│   │                            (both NixOS hosts; see programs/maintenance)
│   ├── virtualization.nix       docker (rootless + socket-activated system daemon)
│   │                            + VirtualBox host
│   ├── networking/
│   │   └── dns.nix              systemd-resolved: pihole first, then mullvad/
│   │                            quad9/cloudflare; opportunistic DoT
│   ├── computers/
│   │   ├── nixos.nix            the desktop host, as data (hostname, NFS mounts)
│   │   ├── harmonia.nix         the cache-server host: headless, own minimal
│   │   │                        base, harmonia service + signing-key secret
│   │   ├── nixos/
│   │   │   ├── _hardware.nix    mounts (by partlabel) + kernel facts
│   │   │   └── _disko.nix       declarative partition layout (disko CLI)
│   │   └── harmonia/
│   │       └── _hardware.nix    the server's hardware scan (manual import;
│   │                            placeholder until adoption — see nix-caches)
│   ├── nixos/
│   │   ├── base.nix             host-agnostic system base (ex-configuration.nix)
│   │   └── flake-source.nix     nixpkgs.flake.source + version metadata
│   └── batman/
│       ├── fish.nix             fish + shell UX
│       ├── fzf.nix              fzf with fd as the file finder
│       ├── git.nix              git identity, signing, aliases
│       ├── gh_cli.nix           gh CLI over ssh protocol
│       ├── ghostty.nix          ghostty terminal (Catppuccin Frappe)
│       ├── ssh.nix              ssh client config; dedicated GitHub push key
│       ├── agenix.nix           user-level secrets + GPG auto-import
│       ├── agents.nix           pi + llm-agents tools, model router
│       ├── nvf.nix              nvf wiring (+ ryan-nvim injection); Linux-only
│       ├── packages.nix         home.packages (messaging, 1Password CLI, build tools)
│       ├── backup.nix           borgmatic + git backup timer (home.pc; desktop)
│       ├── cachix.nix           nix-configs cache: agenix creds + CI secret
│       │                        sync + Mac's declarative nix.conf
│       ├── obsidian.nix         obsidian vault (home.pc; desktop)
│       ├── kodi.nix             kodi media center + IPTV PVR (home.pc; desktop)
│       ├── hypnotix.nix         IPTV player, XWayland-forced (home.pc; desktop)
│       ├── screen-capture.nix   kooha screen recorder (home.pc; desktop)
│       ├── hyprland.nix        Hyprland session stack (home.pc; desktop)
│       ├── time-of-day-gamma.nix KWin Night Light, fixed Denver coordinates
│       │                        (home.pc; desktop)
│       ├── vicinae.nix          vicinae launcher (HM module + NixOS setcap)
│       └── _nvf/
│           └── default.nix      nvf settings module (manual import)
└── scripts/
    └── git-backup.sh            the script the backup timer runs
```

Notes on the machinery files that are not self-explanatory:

- `modules/eval-modules.nix`: a reusable option set (`fn`, `module`, `args`,
  `configuration`) that calls any eval-config-style function with the
  accumulated module; `modules/nixos.nix` instantiates it with
  `import "${inputs.nixpkgs}/nixos/lib/eval-config.nix"` and
  `modules/home.nix` with `homeManagerConfiguration`.
- `modules/nixos/flake-source.nix`: restores what
  `nixpkgs.lib.nixosSystem` injects but plain eval-config loses:
  `nixpkgs.flake.source = mkDefault inputs.nixpkgs.outPath` (keeps
  `<nixpkgs>`/registry resolution working — the fish abbreviation
  `ns = "nix shell nixpkgs#"` depends on it) plus revision-aware
  `system.nixos` version metadata.

Per-feature notes live in [docs/programs/](programs/index.md).
