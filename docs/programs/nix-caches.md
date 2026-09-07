# Nix caches

[← program notes](index.md) · modules: `batman/cachix.nix`, `modules/system/base.nix` (nix.settings), `modules/computers/harmonia.nix`, `modules/lib.nix` (cachixCache)

Four caches in play: the canonical `cache.nixos.org`, the personal
cachix cache **nix-configs**, a LAN harmonia server, and upstream caches
for inputs with their own nixpkgs pins. The goal: no machine (and no CI
runner) should ever build what something else already built.

## Substituter order (desktop, `modules/system/base.nix`)

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

## Installing with the caches (fresh metal / first rebuild)

The repo's substituter set belongs to the **installed system**
(`nix.settings`). The ISO's nix — and the plain NixOS a flash-drive
install produces — know only `cache.nixos.org`, so installs that skip
this section **compile every pinned-input package from source**: the
llm-agents tools (pi and friends, built against their own nixpkgs pin
and compiling node native modules via node-gyp) froze a laptop
install **twice** on 2026-09-05, and even when it doesn't freeze it
costs hours. Export the repo's set first — on the home LAN the full
block (canonical copy = `modules/system/base.nix`):

```sh
export NIX_CONFIG='
substituters = http://192.168.1.82:5000 https://nix-configs.cachix.org https://psysonic.cachix.org https://vicinae.cachix.org https://cache.numtide.com https://cache.nixos.org
trusted-public-keys = nix-cache-1:SpVt1hjpAaEgQqnY1cIm5tjTETZbG5dQmGZ3rDbTyJc= nix-configs.cachix.org-1:7Ujoj71uBp3xoxOBwPF8CTJAmoaz0+I/Dm1yK0dNyBw= psysonic.cachix.org-1:M9cQyQ7tgvUWOQ5Pyt8ozlMoPLtOZir6MfRuTH9/VYA= vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc= niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
'
```

Away from the LAN, drop the harmonia URL **and** its `nix-cache-1`
key from the two lines — an unreachable first substituter just adds
latency, and `nix-configs` still carries what CI builds (including
the real host toplevels, since the `build-hosts` job).

Paste it through `sudo -E` where sudo is involved (`sudo -E
nixos-install …`, `sudo -E nixos-rebuild …` — sudo scrubs the
environment otherwise). The block is all **public** material, but
keep it as a 1Password note (e.g. "nixos-install — substituters") so
an install needs no repo checkout to hand-copy it from — that is the
"bring the substituter keys down from 1Password" step of the
[bootstrap runbooks](../bootstrap.md). After the first switch, the
system's own `nix.settings` take over permanently — the export is
install-time only.

CI's `test-hosts` job builds and boots both desktop-style hosts and
pushes what it builds to `nix-configs`; `build-hosts` builds the
real host toplevels on top of that — so both bare-metal paths above
substitute in minutes.

## The harmonia post-build hook (warm the LAN cache)

Every path this machine **builds** (as opposed to substitutes) is pushed
to the cache server's nix store after the build. Harmonia 3.x serves
that store over HTTP (signing on the fly) but its HTTP upload route is
gone, so pushes go over ssh — and specifically the **legacy `ssh://`
store, deliberately**: locally-built paths are unsigned, and `ssh-ng://`
rejects them at the remote daemon ("lacks a signature by a trusted
key"), while `ssh://` imports via `nix-store --import` as root.

The hook runs as root (nix-daemon) but authenticates with batman's
`/home/batman/.ssh/harmonia` (`IdentityFile` in its `NIX_SSHOPTS`) —
the shared 1Password key that `modules/system/distributed-builds.nix`
also uses to offload builds to .82, authorized on the server as
`framework-remote-build` — but **gated** (2026-09-06): LAN-scoped
(`from="192.168.1.0/24"`), no forwarding, and forced through a command
wrapper (harmonia.nix's `nixStoreServeOnly`) that passes only the nix
store protocol. The fleet-wide key can push store paths; it can never
open a root shell on the box that signs the fleet's binaries.
(This paragraph long claimed
`/root/.ssh/id_ed25519` / `desktop-nix-cache-push`; that key stays
authorized — LAN-scoped now too — and still carries
`sudo nixos-rebuild --target-host` deploys; nothing pushes with it
anymore.) It is wrapped in
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
lab box), root's `authorized_keys` (id_borg as the one admin path,
plus two LAN-scoped restricted machine keys — see the gating note in
the post-build-hook section above), the
firewall (22 + 5000), and sshd. It is deliberately a **slim host**: no
`nixos.modules.base` (no Plasma/home-manager), no user slot — root is
the only account. Deployed from the desktop, never rebuilt on the box:

```sh
sudo nixos-rebuild switch --flake .#harmonia --target-host root@192.168.1.82
```

nixos-rebuild builds locally (substituting from this repo's caches,
including this very cache) and copies the closure over ssh as root via
`/root/.ssh/id_ed25519` (`desktop-nix-cache-push` — a different key
from the hook's, same authorized destination). `nix flake check --no-build`
(= CI) eval-checks the host like any other.

Recovery story once adopted: any fresh NixOS box + this repo + the
host-key recipient in `secrets.nix` re-creates the server; cache
*contents* are derived data that re-accumulates as clients rebuild.

### Bringing .82 under management (one-time)

**Status: done (2026-09-04).** The full runbook walked end-to-end:
real `_hardware.nix` from the box's `nixos-generate-config`, the
disko mirror (`_disko.nix`, `sda` verified), stateVersion confirmed
26.05, the host-key recipient verified against the box, the push key
pasted (the box's authorized_keys held only that one key), labels set
on the live disk, and the first `--target-host` deploy switched the
box — during which the post-build-hook warmed the cache so the
deploy's copy step moved 0 paths, and the server came back serving
signed narinfos under `nix-cache-1`. Retained as reference (and as
the template for adopting any future hand-configured box);
`scripts/adopt-harmonia.sh` automated steps 1–6, 8 and 9.

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

7. Put the real signing secret into
   `secrets/harmonia-signing-key.age`. Either the interactive way
   (`agenix -e secrets/harmonia-signing-key.age`, paste the secret from
   step 4), or the no-paste way — read straight off the box into age,
   never touching disk unencrypted (both recipients come from
   `secrets.nix`):

   ```sh
   cd /etc/nixos
   printf '%s\n' \
     'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIELiz8KiOJ2x7L1J2yx3X8RZkZ3bd/uHcsUH5rzVw8Cl batman@nixos' \
     'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINtxzFwIX6e97M/y8aeL0qdI1lM7IykhxS49fe99c0b0 root@192.168.1.82' \
     > /tmp/harmonia-recipients
   sudo ssh root@192.168.1.82 'cat <signing-key-path-from-step-4>' \
     | nix shell nixpkgs#age -c age -R /tmp/harmonia-recipients \
       -o secrets/harmonia-signing-key.age
   rm /tmp/harmonia-recipients
   grep -c ssh-ed25519 secrets/harmonia-signing-key.age   # expect 2 stanzas
   ```

   Optionally also store the secret in 1Password as belt-and-braces.
8. `sudo cat /root/.ssh/id_ed25519.pub` — paste into
   `users.users.root.openssh.authorizedKeys.keys` in
   `modules/computers/harmonia.nix`, together with any other keys from
   step 6. **This assignment replaces the file on switch** — dropping
   the deploy key means console-only recovery, so diff first. It also
   cannot quietly outlive the rest of adoption: once step 3's real
   hardware file has landed, an eval-time assertion in the host module
   requires a non-empty key list — `nix flake check` (and CI) fail
   until the key is pasted.
9. Recipients are already wired: `secrets.nix` carries the `harmonia`
   host key (keyscan'd from the LAN, trust-on-first-use). At adoption,
   verify it matches the box —
   `ssh root@192.168.1.82 'cat /etc/ssh/ssh_host_ed25519_key.pub'`.
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

For the day-to-day "is it working" check — cache **warmth** against a
real closure — `scripts/harmonia-warmth.sh` asks the server which of a
closure's paths it can serve (any installable, default
`/run/current-system`):

```sh
scripts/harmonia-warmth.sh
# a to-be-deployed host toplevel: build (mostly substitution), then probe
nix build /etc/nixos#nixosConfigurations.harmonia.config.system.build.toplevel
scripts/harmonia-warmth.sh ./result
```

(Installables must already be realised — `nix path-info` cannot walk
an unbuilt closure, so build first and probe the output path; store
paths always work.) Calibration point, 2026-09-06: `/run/current-system`
scored 4033/4033 HIT — the entire running desktop reconstructible
from .82 alone.

### If the VM is ever recreated

Full fresh-metal runbook — recreating the guest, pre-seeding its host
key, re-keying the signing secret, re-warming — lives in
[bootstrap](../bootstrap.md#harmonia-resurrection-runbook-the-cache-vm).

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
GitHub runners cannot reach — and never should: the server is
LAN-only by design, and a CI→LAN tunnel would trade the firewall
posture for a cache cachix already covers. The split is the
architecture: **CI warms the public cache, the desktop's
post-build-hook warms the LAN cache.** Since the harmonia host's
adoption, CI builds that host's toplevel (now the `harmonia` entry
of the `build-hosts` matrix, alongside both desktop toplevels) —
its closure is small and mostly substitutable upstream, so the
entry costs minutes and makes every later `--target-host` deploy a
pure substitution.
