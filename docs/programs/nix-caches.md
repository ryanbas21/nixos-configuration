# Nix caches

[← program notes](index.md) · modules: `batman/cachix.nix`, `modules/nixos/base.nix` (nix.settings), `modules/computers/harmonia.nix`, `modules/lib.nix` (cachixCache)

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

## The server (.82) — tracked in this repo

`modules/computers/harmonia.nix` manages the cache server itself:
`services.harmonia.cache` (defaults match what .82 has served all
along: `[::]:5000`, priority 50), the signing key as an agenix secret
(`secrets/harmonia-signing-key.age` — the secret half of the
`nix-cache-1:...` pair, no longer single-point-of-failure state on a
lab box), root's `authorized_keys` holding the desktop push key, the
firewall (22 + 5000), and sshd. It is deliberately a **slim host**: no
`nixos.modules.base` (no Plasma/home-manager), no user slot — root is
the only account. Deployed from the desktop, never rebuilt on the box:

```sh
sudo nixos-rebuild switch --flake .#harmonia --target-host root@192.168.1.82
```

nixos-rebuild builds locally (substituting from this repo's caches,
including this very cache) and copies the closure over ssh, riding the
same root key the push hook uses. `nix flake check --no-build`
(= CI) eval-checks the host like any other.

Recovery story once adopted: any fresh NixOS box + this repo + the
host-key recipient in `secrets.nix` re-creates the server; cache
*contents* are derived data that re-accumulates as clients rebuild.

### Bringing .82 under management (one-time)

The host file ships with three deliberate placeholders that must be
filled before the first deploy (each is marked `TODO(first deploy)`
inline):

**On the box** (`ssh root@192.168.1.82`):

1. `uname -m` — confirm `x86_64` (the host file assumes x86_64-linux).
2. `nixos-version` and the `stateVersion` in its current
   `/etc/nixos/configuration.nix` — align
   `system.stateVersion` in `modules/computers/harmonia.nix` if it
   isn't 26.05.
3. `nixos-generate-config`, then replace the placeholder content in
   `modules/computers/harmonia/_hardware.nix` with the generated
   `hardware-configuration.nix` (the placeholder's root device is
   intentionally nonexistent — a deploy against it fails loudly).
4. Locate the current signing key: `systemctl cat harmonia` (look at
   `SIGN_KEY_PATHS` / `LoadCredential`), then `cat` that file — its
   content is needed in step 7.
5. `cat /etc/ssh/ssh_host_ed25519_key.pub` — the host's agenix
   identity.
6. `cat ~/.ssh/authorized_keys` — note every key present, not just the
   desktop's.

**On the desktop** (in `/etc/nixos`):

7. `agenix -e secrets/harmonia-signing-key.age` — paste the real
   signing secret from step 4 (the placeholder is batman-encrypted
   exactly so this edit is possible). Optionally also store it in
   1Password as belt-and-braces.
8. `sudo cat /root/.ssh/id_ed25519.pub` — paste into
   `users.users.root.openssh.authorizedKeys.keys` in
   `modules/computers/harmonia.nix`, together with any other keys from
   step 6. **This assignment replaces the file on switch** — dropping
   the deploy key means console-only recovery, so diff first.
9. In `secrets.nix`: uncomment the `harmonia` recipient, paste the host
   pubkey from step 5, and add `harmonia` to the signing key's
   `publicKeys`.
10. Commit and push (CI eval-checks the completed host), then deploy:

    ```sh
    sudo nixos-rebuild switch --flake .#harmonia --target-host root@192.168.1.82
    ```

**Verify** after the switch:

```sh
curl -s http://192.168.1.82:5000/nix-cache-info   # StoreDir/Priority back
sudo nix copy --to ssh://root@192.168.1.82 /nix/store/<any locally-built path>
curl -sf http://192.168.1.82:5000/<that path's basename>.narinfo && echo PUSH WORKS
```

(The manual `nix copy` surfaces errors the hook's `|| true` swallows —
it doubles as the definitive check that the push path, unverified
since the hook landed, actually works.)

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
