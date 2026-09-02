# Nix caches

[← program notes](index.md) · modules: `batman/cachix.nix`, `modules/nixos/base.nix` (nix.settings), `modules/lib.nix` (cachixCache)

Four caches in play: the canonical `cache.nixos.org`, the personal
cachix cache **nix-configs**, a LAN harmonia server, and upstream caches
for inputs with their own nixpkgs pins. The goal: no machine (and no CI
runner) should ever build what something else already built.

## Substituter order (desktop, `modules/nixos/base.nix`)

```
http://192.168.1.82:5000      LAN harmonia (everything this desktop builds)
https://nix-configs.cachix.org personal cachix (what CI builds)
https://psysonic.cachix.org   psysonic flake input (own nixpkgs pin)
https://vicinae.cachix.org    vicinae flake input (gcc15Stdenv, own pin)
https://cache.numtide.com     llm-agents tools (own nixpkgs pin)
https://cache.nixos.org/      canonical
```

Nix tries every trusted key against every substituter — the two lists do
not need to match in order. Notable entries:

- **`vicinae.cachix.org` exists because the vicinae flake input has
  deliberately no `follows` on nixpkgs** — a follows would make the
  cache miss — and its package (built with gcc15Stdenv against its own
  nixpkgs) is not on cache.nixos.org. Without this entry every vicinae
  bump compiles from source. The same logic explains psysonic's and
  numtide's entries: inputs with their own pins have their own caches.
- The LAN harmonia URL is `trusted-substituters` too, so root-level
  builds can use it.

## The harmonia post-build hook (warm the LAN cache)

Every path this machine **builds** (as opposed to substitutes) is pushed
to the cache server's nix store after the build. Harmonia 3.x serves
that store over HTTP (signing on the fly) but its HTTP upload route is
gone, so pushes go over ssh — and specifically the **legacy `ssh://`
store, deliberately**: locally-built paths are unsigned, and `ssh-ng://`
rejects them at the remote daemon ("lacks a signature by a trusted
key"), while `ssh://` imports via `nix-store --import` as root.

The hook runs as root (nix-daemon) and uses `/root/.ssh/id_ed25519`
(authorized on the server as `desktop-nix-cache-push`). It is wrapped in
a `writeShellScript` because nix spawns the hook as a single command
line — inline quoting and shell operators like `||` don't survive that —
and is best-effort (`|| true` inside the script) so a down cache server
can never fail a build. **Which also means a missing key or down server
fails silently** — if the cache seems cold, check
`journalctl -u nix-daemon` after a build.

## nix-configs cachix: the cache as repo state

The personal cachix cache's credentials are **provisions of this repo**,
not machine or GitHub-vault state:

- `secrets/cachix-auth-token.age` + `secrets/cachix-signing-key.age`
  hold the auth token and the **BARE** self-signing secret — exactly the
  format `cachix generate-keypair nix-configs` writes to `cachix.dhall`,
  with **no `name:` prefix** (a prefixed key fails server-side signature
  verification; this cost an evening, twice — see the comments in
  `.github/workflows/ci.yml`).
- On every desktop activation, `cachix.nix` materializes both into
  `~/.config/cachix/cachix.dhall` (fully derived state — edit the `.age`
  files, never the dhall) and syncs them to the repo's GitHub Actions
  secrets (`CACHIX_AUTH_TOKEN` / `CACHIX_SIGNING_KEY`) via `gh secret
  set`, so CI's cache pushes authenticate with repo-owned credentials.
  The sync is best-effort but **loud**: a failure prints a warning (a
  silently stale secret also cost an evening once).
- **Mac:** `~/.config/nix/nix.conf` (substituters + keys + flakes) is
  written declaratively by the home config — single-user nix on macOS
  reads the user config directly, so that is the whole story there.
- **CachyOS laptop:** the one machine this cannot reach — its nix daemon
  is root-owned and only reads `/etc/nix/nix.conf`. One-time sudo step,
  exact lines in [bootstrap](../bootstrap.md#fresh-laptop-runbook-cachyos-user-ryan).

`modules/lib.nix`'s `cachixCache` (URL + public key) is the single
source consumed by both the desktop's `nix.settings` and the Mac's
nix.conf.

## CI side (`.github/workflows/ci.yml`)

The build jobs push every path they create to nix-configs via
`cachix-action`, so later runs (and the desktop) substitute instead of
rebuilding. Three hard-won settings:

- `useDaemon: false` — the daemon's post-build-hook push path does not
  inherit the signing key; uploads went unsigned and every batch 400'd
  server-side *while the step still reported success*. The post-step
  push applies the key correctly.
- `signingKey` carries the BARE secret (see above — do not "fix" it back
  to `name:secret` format).
- `installCommand` stays at the action default — `nix profile install
  nixpkgs#cachix` evaluates unstable nixpkgs, which throws
  "dropped support for x86_64-darwin" on the Intel macOS runner.

The step is skipped when either secret is absent (fork PRs, or before
the cache existed), so the workflow stays green without them. CI's
substituters are the repo's set minus the LAN harmonia server, which
GitHub runners cannot reach.
