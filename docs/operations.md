# Operations

[← README](../README.md) · [Architecture](architecture.md) · [Machines](machines.md)

Day-to-day ritual: updating inputs, deploying, rollback, and what CI checks.

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
   through a session you care about. CI boots both NixOS hosts as VMs
   on every push (`test-hosts`) — with the secret-decrypting hooks
   running against throwaway key material — but a local `test` still
   catches breakage *before* the commit, including the parts CI
   structurally cannot see (real key bytes, hardware).
4. Commit the lock and push. The laptop and Mac need nothing: their
   one-liners read this repository's `flake.lock` straight from GitHub.

Notes on individual inputs:

- `agenix` regularly looks months stale and usually isn't: upstream
  releases rarely, and the locked rev has more than once been HEAD when
  checked. Verify with `nix flake metadata github:ryantm/agenix` before
  treating it as stale (checked 2026-09-01: `b027ee2` is HEAD).
- `nixpkgs-intel-mac` tracks the last x86_64-darwin branch
  (`nixpkgs-26.05-darwin`) and moves only when that branch does.
- `vicinae` deliberately has **no** `follows` on nixpkgs (a follows makes
  its binary cache miss — see
  [nix caches](programs/nix-caches.md#substituter-order-desktop-modulesnixosbasenix)).
- `git-hooks` (the pre-commit flake) follows nixpkgs like everything
  else; only its hook-tool pins move on their own.

Cadence is demand-driven, not calendared: update when a package is needed
newer, or for security fixes — not on a schedule.

## Deployment steady state

**Deployment** needs nothing beyond a clone of this repo. On the desktop the
clone lives at `/etc/nixos`, so the steady state is:

```sh
cd /etc/nixos && git pull
sudo nixos-rebuild switch --flake .#nixos
```

The laptop and Mac deploy with the one-liners in
[Machines](machines.md) — no clone required.

## Rollback & failure recovery

Three tiers, depending on how broken things are:

**Rebuild broke something, system still usable.**
`sudo nixos-rebuild switch --rollback` activates the previous generation
immediately and moves the boot default back. Home-manager rolls back
**with** it — batman's home is activated as part of system activation
(the NixOS-module integration), so there is no separate
`home-manager rollback` step to remember.

**System won't boot.** The systemd-boot menu lists every retained
generation ("NixOS - Generation N" entries). Boot the previous one, then
run `sudo nixos-rebuild switch --rollback` from inside it to make the
choice sticky — otherwise the newest (broken) generation stays the
default. To see what exists:

```sh
sudo nix-env -p /nix/var/nix/profiles/system --list-generations
```

**Data.** A rollback reverts configuration, not data — the borg
repository is the recovery path for files
([backups](programs/backup.md)).

Caveats worth knowing:

- Secrets re-decrypt fine after rollback: the agenix identity
  (`~/.ssh/id_borg`) is user-level state that predates and outlives any
  generation.
- `sudo nixos-rebuild test --flake .#nixos` before `switch` (step 3 of
  the [update ritual](#updating-inputs)) is the cheap way to never need
  this section: it activates without touching boot entries, so a bad
  activation never costs you the boot menu.
- Rollback reach is bounded by [maintenance](programs/maintenance.md):
  the weekly GC keeps 30 days of generations, and
  `boot.loader.systemd-boot.configurationLimit = 10` caps the boot menu —
  the two guardrails are one policy.

## CI (.github/workflows/ci.yml)

CI runs on every push to main and on every pull request, in six jobs:

- **flake-check** — a fast eval-only job (`nix flake check --no-build`)
  covering every output: the NixOS hosts against their tracked hardware
  files, both standalone homes, and the rest. Catches module/option
  breakage after a `nix flake update` in ~1 minute.
- **build-homes** — a matrix job that builds the exact `activationPackage`
  each standalone machine pulls: `ryan-linux` on an x86_64-linux runner,
  `ryan-intel-mac` on GitHub's Intel macOS runners (the last x86_64 images
  Actions offers).
- **build-harmonia** — builds the cache server's small, almost fully
  substitutable closure so every later `--target-host` deploy substitutes
  instead of building (the full story in
  [nix caches](programs/nix-caches.md)).
- **test-harmonia** — boots the real harmonia module as a UEFI QEMU guest
  and proves the cache serves signed narinfos
  (`modules/computers/harmonia/vm-test.nix`) — the resurrection
  guarantee, on every push.
- **test-hosts** — boots the real `nixos` and `framework` modules as UEFI
  QEMU guests and asserts the fresh-boot contract
  ([modules/vm-tests.nix](../modules/vm-tests.nix)): multi-user.target,
  the boot-path home-manager activation, the batman account, core
  services, no failed units. The activation-time secret decryption
  (rage + `~/.ssh/id_borg`: GPG import + ownertrust, cachix dhall
  materialization, the hypnotix dconf write) runs against committed
  throwaway key material — the harmonia vm-test pattern — so the
  decrypt machinery itself is under test on every push; only the real
  key BYTES stay in 1Password. (This is the automation of the
  [bootstrap](bootstrap.md) runbooks' guarantee — and it already paid
  off once: it reproduced the framework laptop's real first-boot
  failure, the bare `dconf write` without a D-Bus session, now fixed
  with the same `dbus-run-session` wrapper home-manager itself uses.)
- **test-disko** — executes every `_disko.nix` for real in VMs
  ([modules/disko-tests.nix](../modules/disko-tests.nix), built on
  disko's own `makeDiskoTest` harness): scratch disk →
  destroy,format,mount (idempotency checked) → minimal NixOS installed
  onto it → that system **booted** as a second VM → every mounted
  filesystem compared against the host's tracked `_hardware.nix`
  mount table. The labels contract — "a disko-formatted disk and the
  live disk satisfy the identical config" — as a test, on every push.

The build jobs push everything they build to the personal cachix
cache (`nix-configs`, self-signed with our own keypair), so later runs
— and bare-metal installs — substitute instead of rebuilding; the full
story, including the credentials provisioning and the war stories, is
in [nix caches](programs/nix-caches.md).

**Validation from anywhere, no hardware needed:** `nix flake check`
(with or without `--no-build`) evaluates the host toplevel against the
real tracked hardware file; `nix build -L
.#checks.x86_64-linux."nixos:vm-test"` boots the host as a VM and
asserts the fresh-boot state (same for `framework` and `harmonia`);
and `nix build -L .#checks.x86_64-linux."disko:framework"` partitions,
formats, installs onto, and BOOTS the disk layout (same for the other
hosts).
