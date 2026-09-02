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
- `vicinae` deliberately has **no** `follows` on nixpkgs (a follows makes
  its binary cache miss — see
  [nix caches](programs/nix-caches.md#substituter-order-desktop-modulesnixosbasenix)).
- The git-backup timer (see [backups](programs/backup.md)) commits and
  pushes any dirty tree — including a half-finished lock update. That is
  safe (CI checks those pushes too), but if the update commit should
  carry a real message, commit before the timer fires.

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

- Rollback vs. repo drift: the [git-backup timer](programs/backup.md)
  keeps pushing repo HEAD regardless. A rolled-back system simply
  disagrees with repo HEAD until the next rebuild from HEAD re-applies
  it. Harmless — don't be surprised by it.
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

CI runs on every push to main (including the backup timer's automated
commits) and on every pull request, in two jobs:

- **flake-check** — a fast eval-only job (`nix flake check --no-build`)
  covering every output: the NixOS host against its tracked hardware file,
  both standalone homes, and the rest. Catches module/option breakage
  after a `nix flake update` in ~1 minute.
- **build-homes** — a matrix job that builds the exact `activationPackage`
  each standalone machine pulls: `ryan-linux` on an x86_64-linux runner,
  `ryan-intel-mac` on GitHub's Intel macOS runners (the last x86_64 images
  Actions offers). Only the NixOS toplevel itself stays unbuilt in CI: a
  full system build on an unpersisted runner costs hours for little
  signal, and build failures there surface at the desktop's
  `nixos-rebuild` anyway.

The build jobs also push everything they build to the personal cachix
cache (`nix-configs`, self-signed with our own keypair), so later runs
substitute instead of rebuilding — the full story, including the
credentials provisioning and the war stories, is in
[nix caches](programs/nix-caches.md).

**Validation from anywhere, no hardware needed:** `nix flake check` (with
or without `--no-build`) evaluates the host toplevel against the real
tracked hardware file.
