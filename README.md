# NixOS configuration

Clone-and-run configuration for every machine in the fleet: a NixOS desktop
(host `nixos`, user batman), a CachyOS laptop (standalone home-manager as
ryan), and an Intel Mac (standalone home-manager as ryan). The repo is
organized as one feature per file: dropping a `.nix` file into `modules/` is
the only step needed to enable it. Neovim is built by nvf, with its lua
sourced from the dotfiles repo through the `ryan-nvim` flake input.

[![CI](https://github.com/ryanbas21/nixos-configuration/actions/workflows/ci.yml/badge.svg)](https://github.com/ryanbas21/nixos-configuration/actions/workflows/ci.yml)

The structure follows the [dendritic pattern](https://github.com/mightyiam/dendritic);
[mightyiam/infra](https://github.com/mightyiam/infra) is the canonical
implementation.

## The big picture

Two repos, three machines:

- **github:ryanbas21/dotfiles** — home of the nvim lua tree, pinned here as
  the `ryan-nvim` flake input and consumed by nvf; its remaining GNU Stow
  configs turn legacy as machines move onto this repo.
- **github:ryanbas21/nixos-configuration** — this repo, the only Nix repo:
  the NixOS desktop's system plus batman's home-manager (fish shell bundle,
  nvf-managed neovim, backups), and the standalone home-manager exports the
  laptop and Mac pull as users `ryan`.

```
github:ryanbas21/dotfiles        (data only; the nvim lua tree)
        |
        | pinned as flake input `ryan-nvim`
        v
github:ryanbas21/nixos-configuration   (this repo; all three machines)
        ├── nixos desktop: system config + batman's home-manager
        ├── ryan-linux:     standalone home-manager for the CachyOS laptop
        └── ryan-intel-mac: standalone home-manager for the Intel Mac
```

## Machines

| Machine | OS | Consume via | Command |
|---|---|---|---|
| Desktop (host `nixos`, user batman) | NixOS | `nixosConfigurations.nixos` | `sudo nixos-rebuild switch --flake .#nixos` |
| CachyOS laptop (user ryan) | Arch-based Linux | `homeConfigurations.ryan-linux` | `nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-linux` |
| Intel Mac (user ryan) | macOS + nix | `homeConfigurations.ryan-intel-mac` | `nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-intel-mac` |

On the desktop the repo lives at `/etc/nixos`, so the steady state is
`git pull` followed by the rebuild command above; the laptop and Mac need
nothing but nix installed. The desktop's git-backup timer operates on
that `/etc/nixos` checkout itself (the path is bound once, as `repoPath`,
in `modules/batman/backup.nix`), so moving the checkout means changing
that binding.

The model in three sentences: NixOS machines are hosts under
`modules/computers/`, each committing its own hardware scan
(`_hardware.nix`; the underscore keeps import-tree away so the host file
imports it manually). Non-NixOS machines consume the standalone
`homeConfigurations` built by `modules/home.nix` — no hardware anything,
user-space only. Both kinds eat the same feature files through
`users.<name>.home.*`, so fish and packages stay identical across the
fleet (modulo the Linux-only bits: nvf, kate, ghostty, sshfs, and the
desktop's backup timers).

### Adding a machine

**New NixOS host:**

2. On the box, run `nixos-generate-config`; copy the generated
   `hardware-configuration.nix` content into
   `modules/computers/<name>/_hardware.nix` (the `_` prefix is required —
   see [Hardware & deployment](#hardware--deployment)).
3. Create `modules/computers/<name>.nix` assigning
   `nixos.configurations.<name>.module`: `system.stateVersion`,
   `nixpkgs.hostPlatform`, the machine's `networking.hostName` and any
   NFS mounts it needs (with `boot.supportedFilesystems = [ "nfs" ]` —
   host-specific data lives here, not in the shared base), and
   `imports = [ ./<name>/_hardware.nix config.nixos.modules.base config.users.<user>.nixos.base ]`.
3. Commit, then `sudo nixos-rebuild switch --flake .#<name>`.
   `nixosConfigurations.<name>` and a flake check appear automatically.

**New standalone machine (any non-NixOS box):** add an entry to
`home.configurations` in `modules/home.nix` (username, system,
homeDirectory) and commit. The Mac entry assumes username `ryan`; if the
account is named differently, change `username` in that entry.

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
   | `home.configurations.<name>` | per-machine data for the standalone home-manager exports |
   | `users.<name>.nixos.base` | the NixOS-side module for a user |
   | `users.<name>.home.base` | the home-manager-side module for a user, all machines |
   | `users.<name>.home.pc` | home.base plus desktop-only extras (backups); NixOS hosts only |

4. `modules/nixos.nix` is machinery: each `nixos.configurations.<name>`
   wraps nixpkgs' `eval-config.nix` and exports, per host:

   - `flake.nixosConfigurations.<name>` — the full evaluation result;
   - `flake.checks."x86_64-linux"."configurations:nixos:nixos"` — the host
     toplevel, so `nix flake check` builds the whole system.

5. `modules/users.nix` wires a user together: the static part of
   `users.batman.nixos.base` declares the batman account (normal user,
   `wheel` + `networkmanager`) and sets
   `home-manager.users.batman = users.batman.home.pc`, so everything the
   batman feature files assign to `users.batman.home.base` (plus the
   desktop-only `home.pc` extras) lands inside home-manager.

6. `modules/home-manager.nix` adds home-manager's NixOS module to
   `nixos.modules.base` (with `useGlobalPkgs` and `useUserPackages`) and sets
   `sharedModules` to `homeManager.modules.base` plus a small module syncing
   `home.stateVersion` from `osConfig.system.stateVersion`.

7. `modules/home.nix` is the standalone counterpart: each
   `home.configurations.<name>` wraps home-manager's
   `homeManagerConfiguration` over `homeManager.modules.base` +
   `users.batman.home.base` (never `home.pc`, and never the osConfig
   stateVersion sync — `osConfig` is null standalone) and exports
   `flake.homeConfigurations.<name>`. The Intel Mac entry builds against
   the `nixpkgs-intel-mac` input because unstable dropped `x86_64-darwin`.

8. `modules/computers/nixos.nix` is the host itself, as data:
   `system.stateVersion = "26.05"`, plain
   `nixpkgs.hostPlatform = "x86_64-linux"`, the hostname, the NFS
   automounts (media, notes, nix-backups) with
   `boot.supportedFilesystems = [ "nfs" ]`, and
   `imports = [ ./nixos/_hardware.nix config.nixos.modules.base  config.users.batman.nixos.base ]` (the hardware import is explained under
   [Hardware & deployment](#hardware--deployment)).

## File tour

```
.
├── flake.nix                    inputs only; delegates to outputs.nix
├── outputs.nix                  mkFlake + import-tree of ./modules
├── flake.lock                   locked input revisions
├── LICENSE                      public domain
├── .gitignore                   result/, .direnv, test-driver history
├── .github/workflows/ci.yml     CI: eval-only flake check + standalone home builds
├── modules/
│   ├── lib.nix                  mkModuleOption helper; shared unfree allowlist
│   ├── eval-modules.nix         generic "wrap any eval-config" machinery
│   ├── nixos.nix                host option tree; nixosConfigurations /
│   │                            checks exports
│   ├── home.nix                 standalone home option tree;
│   │                            homeConfigurations exports
│   ├── home-manager.nix         homeManager.modules.base; wires HM into NixOS
│   ├── users.nix                users.<name>.* slots; declares batman
│   ├── computers/
│   │   ├── nixos.nix            the host, as data (hostname, NFS mounts)
│   │   └── nixos/
│   │       └── _hardware.nix    the desktop's hardware scan (manual import)
│   ├── nixos/
│   │   ├── base.nix             host-agnostic system base (ex-configuration.nix)
│   │   └── flake-source.nix     nixpkgs.flake.source + version metadata
│   └── batman/
│       ├── fish.nix             fish + shell UX
│       ├── nvf.nix              nvf wiring (+ ryan-nvim injection); Linux-only
│       ├── packages.nix         home.packages, ghostty, gh
│       ├── backup.nix           borgmatic + git backup timer (home.pc; desktop)
│       └── _nvf/
│           └── default.nix      nvf settings module (manual import)
└── scripts/
    └── git-backup.sh            the script the backup timer runs
```

Notes on the files that are not self-explanatory:

- `modules/lib.nix`: `mkModuleOption`, the helper behind every module slot
  (delivered to all modules via `_module.args.mkModuleOption`). It types the
  option as `deferredModuleWith` (merging optional `static` modules); its
  `apply` wraps the result with a `key` so merge errors point at the right
  slot. It also carries `unfreeNames`, the single allowlist behind every
  `allowUnfreePredicate` in the repo.
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
  NetworkManager, fish as `users.defaultUserShell`, gnupg agent, sshd,
  Firefox, CUPS, the unfree allowlist (see `modules/lib.nix`), and the
  `nix-command`/`flakes` experimental features. Host-specific data
  (hostname, NFS automounts) does not live here — it stays in
  `modules/computers/<name>.nix`.
- `modules/batman/fish.nix`: fish (cleared greeting; fzf-fish, autopair,
  sponge, done, colored-man-pages plugins; `gco` and `ns` abbreviations)
  plus fzf, starship, zoxide, carapace, eza, direnv + nix-direnv, and
  fzf-git.sh keybindings closed over from `inputs.fzf-git-sh`.
- `modules/batman/packages.nix`: `home.packages` (fd, bat, ripgrep, git,
  gcc, gnumake, sshfs, ghostty, discord, kate) plus ghostty (Catppuccin
  Frappe) and gh (ssh protocol). Kate, ghostty, and sshfs are wrapped in
  `mkIf stdenv.isLinux` — they have no `x86_64-darwin` package, so the Mac
  export skips them.
- `modules/batman/backup.nix`: assigned to `users.batman.home.pc`, so only
  the NixOS host gets it: a daily borgmatic run (Documents to the NFS
  backup mount; 7 daily / 4 weekly retention) and a daily systemd user timer
  running `scripts/git-backup.sh` against the `/etc/nixos` checkout, which
  commits and pushes only when something changed.

## The neovim bridge (nvf + dotfiles lua)

`modules/batman/nvf.nix` enables nvf as a home-manager program and imports
`./_nvf/default.nix` as its settings module. The nvf home-manager module is
imported unconditionally but the program assignment is wrapped in
`mkIf stdenv.isLinux` — nvf's tool bundle has no `x86_64-darwin` story, so
the Mac export carries the module with nvf disabled and the Linux machines
are unaffected. The subtlety is the
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

## Inputs

| Input | Provides |
|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-unstable`; the package set for the system, the desktop's home, and `ryan-linux` |
| `nixpkgs-intel-mac` | `github:NixOS/nixpkgs/nixpkgs-26.05-darwin`; feeds only the `ryan-intel-mac` export, since unstable dropped `x86_64-darwin` |
| `agenix` | secrets: the home-manager module + `agenix` CLI; follows `nixpkgs` |
| `home-manager` | user environments; follows `nixpkgs` |
| `nvf` | the neovim distribution, `github:NotAShelf/nvf/v26.07`; follows `nixpkgs` |
| `ryan-nvim` | `github:ryanbas21/dotfiles`, `flake = false`; the pinned lua tree nvf sources |
| `fzf-git-sh` | `github:junegunn/fzf-git.sh`, `flake = false`; fish keybindings |
| `psysonic` | the psysonic tool (`packages.nix`); own nixpkgs pin |
| `llm-agents` | pi, openskills, plannotator, herdr, rtk (`agents.nix`); own nixpkgs pin |
| `rigup` | the rigup tool (`packages.nix`); own nixpkgs pin |
| `flake-parts` | `mkFlake`, the module system everything runs on |
| `import-tree` | `github:vic/import-tree`, `flake = false`; the auto-importer |

## Updating inputs

The lockfile is the source of truth: no machine moves until a new one is
committed here. The ritual, run on the desktop:

1. `nix flake update` moves every input; `nix flake update <input>` moves
   one. Move `nixpkgs` and `home-manager` together — home-manager master
   tracks nixpkgs-unstable, and a lock where the two diverge is the classic
   source of "option does not exist" eval failures.
2. `nix flake check --no-build` evaluates the NixOS host, both standalone
   homes, and every other output in about a minute. This is exactly what
   CI runs on every push, so this step just moves any failure from a red
   badge on GitHub to before you committed.
3. `sudo nixos-rebuild test --flake .#nixos` builds and activates without
   touching the boot entries; run `switch` once the machine has been
   through a session you care about. CI builds the two standalone homes,
   but the NixOS host itself is only eval-checked there — host build
   failures (an upstream package breaking) still surface here.
4. Commit the lock and push. The laptop and Mac need nothing: their
   one-liners read this repository's `flake.lock` straight from GitHub.

Notes on individual inputs:

- `agenix` regularly looks months stale and usually isn't: upstream
  releases rarely, and the locked rev has more than once been HEAD when
  checked. Verify with `nix flake metadata github:ryantm/agenix` before
  treating it as stale (checked 2026-09-01: `b027ee2` is HEAD).
- `nixpkgs-intel-mac` tracks the last x86_64-darwin branch
  (`nixpkgs-26.05-darwin`) and moves only when that branch does.
- The git-backup timer (see `modules/batman/backup.nix`) commits and
  pushes any dirty tree — including a half-finished lock update. That is
  safe (CI checks those pushes too), but if the update commit should
  carry a real message, commit before the timer fires.

Cadence is demand-driven, not calendared: update when a package is needed
newer, or for security fixes — not on a schedule.

## Hardware & deployment

**Hardware lives in the repo, per host.** The desktop's generated hardware
scan is tracked as `modules/computers/nixos/_hardware.nix` — machine-local
data, kept next to its host file. The underscore prefix matters: the file is
a NixOS module (`imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];`) that would infinitely recurse if
import-tree auto-imported it as a flake-parts module; the `/_` in its path
keeps it manual, and `modules/computers/nixos.nix` imports it explicitly.

**Deployment** needs nothing beyond a clone of this repo. On the desktop the
clone lives at `/etc/nixos`, so the steady state is:

```sh
cd /etc/nixos && git pull
sudo nixos-rebuild switch --flake .#nixos
```

The laptop and Mac deploy with the one-liners in
[Machines](#machines) — no clone required.

**When hardware changes** (a disk swap, a new partition layout): run
`nixos-generate-config` on the machine, copy the generated
`hardware-configuration.nix` content into
`modules/computers/nixos/_hardware.nix`, and commit it.

**Validation from anywhere, no hardware needed:** `nix flake check` builds
the host toplevel against the real tracked hardware file. CI
(`.github/workflows/ci.yml`) does both halves of that on every push to
main (including the backup timer's automated commits) and on every pull
request: a fast eval-only job (`nix flake check --no-build`) covering
every output, plus a matrix job that builds the exact `activationPackage`
each standalone machine pulls — `ryan-linux` on an x86_64-linux runner,
`ryan-intel-mac` on GitHub's Intel macOS runners. Only the NixOS toplevel
itself stays unbuilt in CI; its build failures surface at the desktop's
`nixos-rebuild`. The build jobs also push everything they build to the
personal cachix cache (`nix-configs`, self-signed with our own keypair;
active while its `CACHIX_AUTH_TOKEN` and `CACHIX_SIGNING_KEY` repo
secrets exist), so later runs substitute instead of rebuilding, and the
laptop/Mac pull the same paths after a one-time `nix.conf` entry.

Secrets & agenix

Secrets are encrypted with agenix and committed to this repository. The encrypted .age files are safe to store in Git; the private keys used to decrypt them are never stored in the repository.

The recipient key declared in secrets.nix is batman — the desktop's ~/.ssh/id_borg: the user-level agenix identity, it decrypts every secret. Its private half is backed up in 1Password, so a machine-plus-NAS disaster still leaves a recovery path. GitHub pushes use a separate dedicated key, ~/.ssh/git (declared in modules/batman/ssh.nix).

The repository has this layout:

/etc/nixos/
├── secrets.nix
└── secrets/
    ├── borg-passphrase.age   user-level (borgmatic)
    ├── zai-api-key.age       user-level (fish, agents)
    └── gpg.age               user-level (GPG private-key import)

secrets.nix contains only public recipient keys and is safe to commit. The .age files contain the encrypted secret material and are also committed. Never commit a private decryption key (for example ~/.ssh/id_borg).

Adding a secret

Make sure the recipient's public SSH key is present in secrets.nix. For example:

let
batman = "ssh-ed25519 AAAA... batman@nixos";
in
{
"secrets/example.age".publicKeys = [ batman ];
}

Create or edit the encrypted secret from the repository root (agenix is on the desktop's package list, pinned by the flake input):

cd /etc/nixos
agenix -e secrets/<name>.age

Enter the plaintext secret in the editor. Agenix encrypts it when the editor is closed, using the recipients from secrets.nix.

Add the encrypted file to Git so Nix flakes can see it:

git add secrets/<name>.age

Declare the secret in the Home Manager feature that consumes it:

age.identityPaths = \[
"${config.home.homeDirectory}/.ssh/id_borg"
\];

age.secrets.<name> = {
file = ../../secrets/<name>.age;
};

Consume the decrypted secret through config.age.secrets.<name>.path. For example, a systemd service can use it as an EnvironmentFile:

systemd.user.services.example = {
Service.EnvironmentFile =
config.age.secrets.<name>.path;
};

Important Git rule

The encrypted .age file must be Git-tracked because this repository is a flake. Nix evaluates the flake from its Git source and will reject an untracked secret file.

It is therefore expected to see:

git add secrets/<name>.age

before rebuilding.

The plaintext secret and the private decryption key must never be added to Git.
