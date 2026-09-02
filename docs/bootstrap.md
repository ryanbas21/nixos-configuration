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
ZAI key, both cachix credentials, and (since the harmonia server was
brought under management) the cache's signing key.

## Fresh desktop runbook (same hardware)

Partitioning is declarative (disko layout at
`modules/computers/nixos/_disko.nix`; see
[machines → hardware](machines.md#hardware)) — the runbook has no manual
partitioning or installer-menu steps:

1. **Boot the NixOS ISO** (recent minimal ISO; connect networking —
   `nmtui` or plug in ethernet). Everything on the target disk is
   about to be wiped; borg first if anything matters.

2. **Partition declaratively** — disko creates GPT + `nixos-ESP` (2G)
   + `nixos-root` (btrfs) and mounts them under `/mnt`:

   ```sh
   nix run github:nix-community/disko -- -m destroy,format,mount \
     -f github:ryanbas21/nixos-configuration#nixos \
     --option experimental-features "nix-command flakes"
   ```

   (The `--option` is only needed if the ISO's nix predates flakes —
   recent ISOs ship with them. If the repo is private, clone it first —
   https + token or USB stick — and pass `-f /path/to/clone#nixos`.)

3. **Restore the keys onto the target**, so first-boot activation can
   decrypt (the rebuild creates batman/UID 1000 itself — no manual user
   creation):

   ```sh
   install -D -m 600 <id_borg material> /mnt/home/batman/.ssh/id_borg
   install -D -m 600 <git material>   /mnt/home/batman/.ssh/git
   ```

4. **Install and fix ownership**:

   ```sh
   sudo nixos-install --flake github:ryanbas21/nixos-configuration#nixos \
     --option experimental-features "nix-command flakes"
   sudo nixos-enter -- chown -R batman: /home/batman/.ssh
   ```

5. **Reboot**, remove the USB, and do the post-boot manual state
   (interactive, cannot be declarative):

   - clone the repo into batman's home (so the user-level git-backup
     timer can commit it, and so it rides along in the borg backup of
     `$HOME`) and symlink `/etc/nixos` at it — the desktop's actual
     layout:

     ```sh
     git clone git@github.com:ryanbas21/nixos-configuration.git ~/programming/nixos
     sudo rm -rf /etc/nixos-generated 2>/dev/null; sudo ln -sfn /home/batman/programming/nixos /etc/nixos
     ```

   - `gh auth login` — unblocks the CI cachix-secret sync (the
     activation hook warns until this is done);
   - sign in to 1Password (account, then biometric unlock —
     `OP_BIOMETRIC_UNLOCK` is already set in fish);
   - connect to Wi-Fi networks if any (NetworkManager state);
   - optionally restore `/root/.ssh/id_ed25519` for harmonia cache
     warming (see the key inventory above);
   - **restore data** with borgmatic — the repos live on
     `/mnt/nix-backups` (NFS, mounts on access); `Documents` (including
     the Obsidian vault) is the bulk of it.

   On this first-boot system the repo's config is already active
   (nixos-install activated it), so no separate first rebuild is
   needed — the next `git pull && sudo nixos-rebuild switch` is just
   the steady state.

## Adopting the existing disk (one-time)

The live (hand-partitioned) disk predates disko. Its mounts moved from
UUID to PARTLABEL — the same labels `_disko.nix` sets on fresh installs
— so both disks satisfy the identical `_hardware.nix`. Before the next
rebuild on the existing machine, set the labels once (metadata-only,
safe on a mounted disk, reversible the same way):

```sh
SGDISK=$(nix build --no-link --print-out-paths nixpkgs#gptfdisk)/bin/sgdisk
sudo "$SGDISK" --change-name=3:nixos-ESP --change-name=4:nixos-root /dev/nvme0n1
ls -l /dev/disk/by-partlabel/nixos-*   # both symlinks must appear
```

(`sgdisk` ships in `gptfdisk`, which the system config deliberately
doesn't install permanently — the absolute store path sidesteps both
the missing package and sudo's PATH scrubbing.)

**Order matters:** label first, then `git pull && sudo nixos-rebuild
switch --flake .#nixos`. Rebuilding before labeling leaves `/` and
`/boot` unmountable at boot (recoverable from an older boot-menu
generation, but avoid it — labeling takes five seconds). The disk's
p1/p2 are dead leftovers from a previous install; harmless, ignored,
and wiped whenever a disko run happens.

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
  The server itself is now a tracked host (see
  [nix caches](programs/nix-caches.md#the-server-82--tracked-in-this-repo));
  until the [adoption runbook](programs/nix-caches.md#bringing-82-under-management-one-time)
  is completed, its placeholders make deploys fail loudly rather than
  half-apply — and an eval-time assertion cross-locks the empty
  authorized_keys placeholder against the hardware placeholder, so CI
  flags a still-empty key list the moment the host becomes deployable.

### Deliberate: no impermanence

Opt-in state ("erase your darlings" — wipe `/` every boot, persist-list
everything that must survive) was considered and **rejected** for this
fleet. A Plasma desktop with 1Password, docker volumes, kodi, obsidian,
NetworkManager, and fish history is the pattern's worst case: weeks of
discovering the persist list by breakage, and every new app a potential
silent reset. The risk it would structurally eliminate — configuration
drift — is already covered by convention here (declarative config +
lockfile), by borg (data), and by this runbook (fresh-machine recovery).
The residual class it would uniquely catch — "works only because of an
untracked file" — is the target of the planned fresh-boot VM smoke
[CI test](operations.md#ci-githubworkflowsciyml) backlog item. Revisit
only if that test proves insufficient.
