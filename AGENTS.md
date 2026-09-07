# AGENTS.md — the contract for coding agents in this repo

NixOS flake for the fleet: desktop (`nixos`), Framework laptop
(`framework`), LAN cache server (`harmonia`); standalone
home-manager for the CachyOS laptop (`ryan-linux`) and the Intel Mac
(`ryan-intel-mac`). One feature per file, auto-imported. The full
pattern is [docs/architecture.md](docs/architecture.md); this file is
the minimum that keeps an agent's changes from fighting the
architecture.

## The rules that matter most

1. **Drop a `.nix` file into `modules/` to enable a feature; delete
   it to remove.** There are no `imports = [ ./foo.nix ]` lists
   between feature files — never add one.
2. **`/_` in a path means manual import** (host data: `_hardware.nix`,
   `_disko.nix`; nvf settings data). Don't "fix" these into
   auto-import.
3. **Feature files only assign to option namespaces** —
   `nixos.modules.base` (shared system tier), `users.batman.home.base`
   / host-scoped user tiers (user features), `nixos.configurations.<host>`
   (host wiring). They never import each other. No
   `specialArgs`/`extraSpecialArgs`: close over `inputs` directly
   (`{ inputs, ... }: { ... inputs.agenix ... }`).
4. **Lower-level modules are data**: they live inside option values
   typed `deferredModule` (via `mkModuleOption`, modules/lib.nix) and
   the machinery files (modules/nixos.nix, modules/home.nix,
   eval-modules.nix) feed them to the real evaluations. Don't eval
   anything yourself — assign.
5. **harmonia is deployed, never edited on the box.** From the
   desktop: `just deploy-harmonia` (a `--target-host` rebuild). Its
   root keys, firewall, and cache config are repo state.

## Before you commit

- `just check` (`nix flake check --no-build`, ~1 min) — CI's
  flake-check job runs exactly this. Never push an eval that hasn't
  passed it.
- Host-touching changes: the VM tests are the contract —
  `just test-host nixos` (or `framework`/`harmonia`) boots the real
  host module as a UEFI guest and asserts the fresh-boot state;
  `just test-disko <host>` executes and boots the disk layout.
- `nix develop` installs the pre-commit hooks (deadnix: unused
  lambda args fail the commit).
- Commit style: `area: summary`, lowercase area, one line — see
  `git log`.
- **Stage only the files your change owns.** The working tree often
  carries the human's WIP (`git status` first); sweeping unrelated
  dirty files into a commit is the classic agent failure here.

## Things that bite

- **Feature files take `{ ... }` or `{ inputs, ... }` — never `pkgs`.**
  The deferred-module merge runs in the outer flake-parts eval, where
  `pkgs` does not exist ("attribute 'pkgs' missing"). Bind it house-style:
  `let pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;` (see
  `system/observability.nix`, `system/kernel-hardening.nix`). Host
  modules (`nixos.configurations.<host>.module`, like `computers/harmonia.nix`)
  are different: those DO get `{ config, lib, pkgs, ... }`.
- **`nixpkgs` and `home-manager` move together** — a lock where they
  diverge is the classic "option does not exist" eval failure
  (`just upp` one at a time, but those two as a pair).
- **Secrets are agenix-encrypted and committed**; adding or changing
  one follows [docs/secrets.md](docs/secrets.md). Never write a
  secret's plaintext into the repo, a commit message, or command
  output. Real key material lives in 1Password; CI tests decrypt
  against committed throwaway keys only.
- **Every feature file carries a header comment** (what it does, why
  it exists); the long story goes in `docs/programs/<topic>.md`. A
  change without its doc is incomplete.
- CI pushes what it builds to cachix `nix-configs`; the LAN harmonia
  server is warmed by the desktop-style hosts' post-build-hooks (the
  desktop does the bulk). Runners cannot reach the LAN (by design) —
  don't try. **Never enable `nix.gc` on harmonia**: every cached path
  is unreachable, so any collect sweeps the cache (a weekly timer ate
  38.4 GiB before the eval assertion in `computers/harmonia.nix`
  landed).
- `flake.lock` is the reproducibility anchor: updates are deliberate
  commits, never side effects.

## Commands

`just <recipe>` — see the [Justfile](Justfile) (`just` with no args
lists them). The ritual and steady state behind them:
[docs/operations.md](docs/operations.md).
