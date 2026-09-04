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
| `.82` ssh **host** key | nowhere yet — save to 1Password at adoption, or rely on the rekey path | the cache server's agenix identity (decrypts `harmonia-signing-key.age` on that box) | Nothing is lost: the [resurrection runbook](#harmonia-resurrection-runbook-the-cache-vm) generates a fresh key and rekeys the secret to it |

Restore with correct permissions: `chmod 600`.

Everything else secret-shaped is already in the repo as `.age` files
(see [secrets.md](secrets.md)) — the GPG key, the borg passphrase, the
ZAI key, both cachix credentials, and (since the harmonia server was
brought under management) the cache's signing key.

### Rehearsing the runbook in a VM (optional, before a reinstall)

The whole runbook can be walked end-to-end against a scratch disk
before a real reinstall ever depends on it. The `-device nvme` trick
makes the guest see `/dev/nvme0n1`, the exact device the tracked
layout pins, so no repo edits are needed:

```fish
nix shell nixpkgs#qemu -c qemu-img create -f qcow2 /tmp/rehearsal.qcow2 40G
nix shell nixpkgs#qemu -c qemu-system-x86_64 -enable-kvm -m 6G -smp 3 \
  -cdrom ~/Downloads/nixos-minimal*.iso \
  -drive file=/tmp/rehearsal.qcow2,if=none,id=d0 \
  -device nvme,drive=d0,serial=nixos \
  -nic user
```

Then walk the fresh-desktop runbook top to bottom inside the VM
(user-mode NAT gives network; connect per the ISO's method). The
install pulls the closure from cache.nixos.org over NAT — expect it
slower than bare metal.

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
   creation). First get each private key onto the ISO machine as a
   plain file — staged anywhere (/tmp, a mounted stick); the `install`
   below moves it to its final home on /mnt. Practical routes:

   - **USB stick**: save the two private keys as files from 1Password
     on another device, then on the ISO `mount /dev/sdX1 /tmp/stick`;
   - **graphical ISO**: 1Password web vault in the browser → download
     the keys;
   - **paste**: `nano /tmp/id_borg` and type/paste from another device
     showing the key.

   ```sh
   install -D -m 600 /tmp/<id_borg> /mnt/home/batman/.ssh/id_borg
   install -D -m 600 /tmp/<git>     /mnt/home/batman/.ssh/git
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

## What the ISO install actually does

There is no installer. The ISO is a live NixOS — nix, flakes, a recent
kernel with drivers, network — and "installing" is building the system
closure and copying it onto the target disk:

1. **disko** evaluates `diskoConfigurations.nixos` and runs the
generated `sgdisk`/`mkfs`/`mount` scripts. Result: a partitioned,
labeled, formatted disk with `/` and `/boot` mounted under `/mnt`.
Nothing about the system itself — the repo's `_hardware.nix` already
knows how to mount this layout; that's the labels contract.
2. **the two `install` calls** drop the identity keys into
   `/mnt/home/batman/.ssh` (plain coreutils: `mkdir -p` + `cp` +
   `chmod` in one step, so the key is never briefly world-readable).
   They must exist before first boot: activation — home-manager
   included, agenix decryption included — runs at boot, as batman.
3. **`nixos-install`** evaluates the flake (in the ISO's store),
   substitutes/builds the entire closure, copies it into the target's
   store, creates system profile generation 1, and runs activation in
   the target chroot — which creates the batman user and installs
   systemd-boot plus its first menu entry onto the ESP. It also prompts
   once to set the **root password** (interactive on purpose — console
   recovery only; every real access is via batman + sudo).
4. **`nixos-enter`** is chroot-into-`/mnt`: the `chown` resolves
   `batman` through the *target's* user database, where the account now
   exists (uid 1000) — the ISO's own `/etc/passwd` has no batman.
5. **reboot** — systemd boots generation 1 and activates everything:
   NetworkManager, the backup timers, Night Light, the agenix secrets,
   the whole home. There is no setup phase; the first boot IS your
   machine.

Two nuances worth knowing:

- **The ISO's nix uses the ISO's substituters** (`cache.nixos.org`),
  not the repo's `nix.settings` — those belong to the *installed*
  system. On the LAN, the install can be sped up by exporting the
  repo's substituter set first (`NIX_CONFIG=... sudo -E nixos-install
  ...`, keys from `modules/nixos/base.nix`).
- **No checkout survives the install**: `--flake github:...` leaves no
  `/etc/nixos` — hence the post-boot clone + symlink step in the
  runbook.

Because the store is content-addressed, the closure that lands on the
new disk is bit-for-bit what its hash says — the ISO was only ever the
vehicle that built it.

## Adopting the existing disk (one-time) — completed 2026-09-02

**Status: done.** Labels set, the rebuild landed (fstab by partlabel,
boot menu pruned to 10); the live disk and a fresh disko-formatted
 disk are interchangeable. Retained as reference for adopting any
future hand-partitioned disk.

The live (hand-partitioned) disk predates disko. Its mounts moved from
UUID to PARTLABEL — the same labels `_disko.nix` sets on fresh installs
— so both disks satisfy the identical `_hardware.nix`. The labels get
set once (metadata-only, safe on a mounted disk, reversible the same
way):

```sh
SGDISK=$(nix build --no-link --print-out-paths 'nixpkgs#gptfdisk^out')/bin/sgdisk
sudo "$SGDISK" --change-name=3:nixos-ESP --change-name=4:nixos-root /dev/nvme0n1
ls -l /dev/disk/by-partlabel/nixos-*   # both symlinks must appear
```

(`sgdisk` ships in `gptfdisk`, which the system config deliberately
doesn't install permanently — the absolute store path sidesteps both
the missing package and sudo's PATH scrubbing. The `^out` matters:
recent nix prints every output (`out` *and* `man`) for
`--print-out-paths`, and the multi-path capture breaks both the bash
and fish forms. Fish users: `set SGDISK (nix build --no-link
--print-out-paths 'nixpkgs#gptfdisk^out')/bin/sgdisk`.)

**Order matters:** label first, then `git pull && sudo nixos-rebuild
switch --flake .#nixos`. Rebuilding before labeling leaves `/` and
`/boot` unmountable at boot (recoverable from an older boot-menu
generation, but avoid it — labeling takes five seconds). The disk's
p1/p2 are dead leftovers from a previous install; harmless, ignored,
and wiped whenever a disko run happens.

## Harmonia resurrection runbook (the cache VM)

The cache server is a QEMU/KVM guest. Its *contents* (cached store
paths) are deliberately not reproducible — the cache re-warms itself
from the desktop's builds via the post-build-hook, which is its whole
design. What **is** reproducible: the VM's disk layout, system, and
signing identity.

### The VM spec (what is and is not in the repo)

| fact | value | status |
|---|---|---|
| machine | QEMU/KVM guest, x86_64 (`qemu-guest` profile) | verified 2026-09-04 |
| disk | single 64G virtual disk, IDE/SCSI presentation → `/dev/sda`; emulated cdrom `sr0` | verified |
| boot | UEFI + systemd-boot | verified (systemd-boot requires UEFI) |
| layout | `harmonia-ESP` 1023M + `harmonia-root` ext4 | `modules/computers/harmonia/_disko.nix` |
| address | 192.168.1.82 via DHCP — the **router reservation** is outside the repo | TODO at adoption: confirm reservation |
| shell | hypervisor host, vCPU/RAM, NIC model | TODO at adoption: fill in |

### Resurrect

1. **Recreate the VM** on whatever hypervisor ran it (fill the spec
   table once known). Two presentation details the tracked layout
   pins: the disk must land on `/dev/sda` — IDE/SCSI presentation; a
   virtio-blk disk lands on `/dev/vda`, so either fix the two device
   fields in `_disko.nix` or present the disk as IDE — and the guest
   must boot **UEFI**, because systemd-boot does not boot from BIOS.
   The
   [rehearsal recipe](#rehearsing-the-runbook-in-a-vm-optional-before-a-reinstall)
   shows the qemu-img/qemu pattern; add OVMF for UEFI
   (`-drive if=pflash,format=raw,file=…/OVMF_CODE.fd` plus a writable
copy of `OVMF_VARS.fd`).
2. **Boot the NixOS minimal ISO in the VM**, partition and mount:

   ```fish
   nix run github:nix-community/disko -- -m destroy,format,mount \
     -f github:ryanbas21/nixos-configuration#harmonia
   ```

   No adoption relabel step here — disko *sets* the
   `harmonia-{ESP,root}` labels itself; that step exists only for
   adopting a hand-partitioned disk.

3. **Pre-seed the host key before install.** The signing secret is
   age-encrypted to the host key, so the key must exist *before*
   activation — otherwise nixos-install's agenix step fails to
   decrypt (openssh would generate a key only later; it keeps
   pre-existing ones):

   ```sh
   mkdir -p /mnt/etc/ssh
   ssh-keygen -t ed25519 -N "" -f /mnt/etc/ssh/ssh_host_ed25519_key
   cat /mnt/etc/ssh/ssh_host_ed25519_key.pub   # → to the desktop
   ```

   If the OLD host key was saved to 1Password, restore it to
   `/mnt/etc/ssh/` instead and skip step 4 entirely.
4. **On the desktop, rekey the secret to the new host key** (batman's
   key can always decrypt — 1Password backup): update the `harmonia`
   recipient in `secrets.nix` with the `.pub` from step 3, then run
   `agenix -r` (re-encrypts every secret for its current recipients;
   only the harmonia one gains the new host key). Commit and push.
   Clients' `trusted-public-keys` pin the *signing* key
   (`nix-cache-1:…`), which did not change — the rekey only changes
   who may *read* the secret.
5. **Install, from inside the VM:**

   ```sh
   nixos-install --flake github:ryanbas21/nixos-configuration#harmonia
   ```

   (the root-password prompt is the console-recovery path only).
   Reboot into generation 1: the box comes up headless, serving
   `:5000`, LAN-scoped firewall, zram swap — no setup phase.
6. **On the desktop, heal the new host identity.** The post-build-hook
   self-heals (`StrictHostKeyChecking=accept-new`), but interactive
   rebuilds need the stale known_hosts entry gone first:

   ```sh
   ssh-keygen -R 192.168.1.82   # the next deploy re-trusts
   ```

7. **Re-warm.** The cache starts empty and fills as the desktop
   builds. To force-warm the current system closure:

   ```sh
   sudo nix copy --to ssh://root@192.168.1.82 /run/current-system
   ```

The signing secret never left the repo (repo state since adoption);
a resurrection's only fresh decisions are the host identity
(steps 3–4) — after that, the cache refills on its own.

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
  adoption landed its real hardware file, disko mirror, and verified
  stateVersion on 2026-09-04, and the fresh-metal path is documented
  ([resurrection runbook](#harmonia-resurrection-runbook-the-cache-vm)).
  Everything landed 2026-09-04 — real hardware file, disko mirror,
  verified stateVersion, verified host-key recipient, push key in
  authorized_keys, the one-time sgdisk relabel, and the first
  `--target-host` deploy (which the cache itself warmed: the desktop's
  post-build-hook pushed the new closure before the deploy's own copy
  step ran, so it copied 0 paths). The box is fully under management;
  see the [adoption runbook](programs/nix-caches.md#bringing-82-under-management-one-time)
  and [resurrection runbook](#harmonia-resurrection-runbook-the-cache-vm).

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
