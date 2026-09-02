# Bootstrap & recovery

[← README](../README.md) · [Machines](machines.md) · [Operations](operations.md) · [Secrets](secrets.md)

**The reproducibility contract.** Everything needed to *configure* a
machine is in this repo and pinned by `flake.lock`: system config,
home-manager config, the hardware scan, all packages, and every secret
(encrypted with agenix). What is *not* in the repo — by design — is a
small set of SSH identity keys (whose plaintext must never be committed)
and interactive/account state. Restore the keys from 1Password, run one
rebuild, and the machine is back.

## What is reproducible automatically

On `sudo nixos-rebuild switch --flake .#nixos`, activation also:

- creates the batman account (wheel, networkmanager, docker, vboxusers)
  with fish as the shell — no manual user setup;
- decrypts every secret into `/run/user/1000/agenix` (tmpfs, never on
  disk): the borg passphrase, the ZAI API key, the cachix credentials;
- imports the GPG private key and pins its ownertrust — git commit
  signing works immediately, no `gpg --edit-key`;
- writes `~/.config/cachix/cachix.dhall` from the agenix secrets and
  syncs `CACHIX_AUTH_TOKEN` / `CACHIX_SIGNING_KEY` to the repo's GitHub
  Actions secrets (loudly warns if `gh` is not authenticated yet — see
  [nix caches](programs/nix-caches.md));
- pins GitHub's host key system-wide, so unattended pushes never prompt;
- starts the daily borgmatic and git-backup timers;
- sets up the NFS automounts (media, notes, nix-backups) on demand.

## The key inventory (the only must-restore items)

| Key | Where | Required for | Consequence if missing |
|---|---|---|---|
| `~/.ssh/id_borg` | 1Password | agenix decryption of **every** secret | **First rebuild fails** — home-manager activation cannot decrypt; restore before rebuilding |
| `~/.ssh/git` | 1Password | pushes to GitHub (git-backup timer, manual pushes, `gh` over ssh) | Timer pushes fail; rebuild still succeeds |
| `/root/.ssh/id_ed25519` | 1Password | the harmonia post-build-hook cache push (authorized as `desktop-nix-cache-push` on the cache server) | **Silently** degrades — builds succeed but nothing warms the LAN cache (`|| true` by design); no warning is printed |

Restore with correct permissions: `chmod 600`.

Everything else secret-shaped is already in the repo as `.age` files
(see [secrets.md](secrets.md)) — the GPG key, the borg passphrase, the
ZAI key, and both cachix credentials.

## Fresh desktop runbook (same hardware)

> **Different hardware** (new box, new disk layout)? The tracked
> `_hardware.nix` belongs to the old machine — regenerate it first, see
> [machines](machines.md#hardware).

1. **Install NixOS** from the ISO. Create the user `batman` during
   install so it gets UID 1000 (matches the restored data's ownership).
   Keep the generated `/etc/nixos` around as `hardware-configuration.nix`
   reference; the repo carries its own scan.

2. **Restore the keys** from 1Password:

   ```sh
   install -D -m 600 <key material> ~/.ssh/id_borg
   install -D -m 600 <key material> ~/.ssh/git
   ```

3. **Accept GitHub's host key once** (the system-wide pin only exists
   after the first rebuild; verify the fingerprint against
   <https://api.github.com/meta> if paranoid):

   ```sh
   ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts
   ```

4. **Clone the repo and symlink `/etc/nixos` at it** — the checkout
   lives in batman's home (so the user-level git-backup timer can commit
   it, and so it rides along in the borg backup of `$HOME`), and
   `/etc/nixos` is a symlink to it (the desktop's actual layout):

   ```sh
   git clone git@github.com:ryanbas21/nixos-configuration.git ~/programming/nixos
   sudo mv /etc/nixos /etc/nixos-generated
   sudo ln -s /home/batman/programming/nixos /etc/nixos
   ```

5. **First rebuild.** The fresh install's nix still has flakes disabled
   (the generated config leaves them off; the repo enables them itself
   from the first successful rebuild on):

   ```sh
   cd /etc/nixos
   sudo nixos-rebuild switch --flake .#nixos \
     --option experimental-features "nix-command flakes"
   ```

   The first build substitutes what it can from the caches (cachix,
   cache.nixos.org, and the LAN harmonia server at `192.168.1.82` if the
   NAS is up) and compiles the rest — expect it to take a while. A down
   NAS only slows things down; it never fails the build.

6. **Post-boot manual state** (interactive, cannot be declarative):

   - `gh auth login` — unblocks the CI cachix-secret sync (the activation
     hook warns until this is done);
   - sign in to 1Password (account, then biometric unlock —
     `OP_BIOMETRIC_UNLOCK` is already set in fish);
   - connect to Wi-Fi networks if any (NetworkManager state);
   - optionally restore `/root/.ssh/id_ed25519` for harmonia cache
     warming (see the key inventory above).

7. **Restore data** with borgmatic — the repos live on
   `/mnt/nix-backups` (NFS, mounts on access). `Documents` (including
   the Obsidian vault) is the bulk of it.borg will list/extract.

## Fresh laptop runbook (CachyOS, user ryan)

1. Install nix (the multi-user daemon) if not already present.
2. **One-time sudo step** — the root nix daemon only reads
   `/etc/nix/nix.conf`, which home-manager cannot touch:

   ```
   substituters = https://nix-configs.cachix.org https://cache.nixos.org
   trusted-public-keys = nix-configs.cachix.org-1:7Ujoj71uBp3xoxOBwPF8CTJAmoaz0+I/Dm1yK0dNyBw= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
   ```

3. Deploy:

   ```sh
   nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-linux
   ```

   If the fresh nix has flakes disabled, prefix with
   `--option experimental-features "nix-command flakes"` (after the
   switch, `~/.config/nix/nix.conf` is *not* managed here — that file is
   the root daemon's, hence step 2).

## Fresh Mac runbook (Intel, user ryan)

1. Install nix — the Determinate installer is the easy path (and enables
   flakes by default; with the official installer prefix the first
   command with the `--option` flag as above).
2. Deploy:

   ```sh
   nix run home-manager -- switch --flake github:ryanbas21/nixos-configuration#ryan-intel-mac
   ```

The Mac's `~/.config/nix/nix.conf` (substituters + keys + flakes) is
written **declaratively** by the home config
(`modules/batman/cachix.nix`) — no manual step.

## What is intentionally NOT reproducible

Data and account state — restore or re-authenticate, don't expect Nix:

- home directory data (borgmatic's job — `Documents`, the Obsidian
  vault's content, `~/.config` leftovers of non-managed apps);
- 1Password account, browser profiles/sessions, Wi-Fi credentials;
- `gh` authentication; docker images/volumes; kodi's library/settings;
- pi agent runtime state (settings.json is managed, but pi's own
  installed packages/telemetry land outside it).

## Residual risks (known, accepted)

- The NixOS toplevel is **eval**-checked in CI but not **built** there;
  a broken upstream package surfaces at the desktop's
  `nixos-rebuild` (see [operations](operations.md#ci-githubworkflowsciyml)).
- The harmonia push hook fails silently when its key or the server is
  missing (by design, so a down NAS can't fail builds) — check
  `journalctl -u nix-daemon` after a big build if the cache seems cold.
