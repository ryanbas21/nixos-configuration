# Backups

[← program notes](index.md) · modules: `batman/backup.nix`, `scripts/git-backup.sh`

Desktop-only: assigned to `home.pc`, not `home.base`, so the standalone
home-manager exports (laptop, Mac) never inherit the backup timers or
the NFS-mount-dependent borgmatic config. Two halves: data (borgmatic)
and config (the git timer).

## Borgmatic (data)

A daily user-level borgmatic run:

- **Sources:** `$HOME` (the whole home, which includes the actual repo
  checkout at `~/programming/nixos` and the Obsidian vault under
  `Documents`) and the repo path (`repoPath` = `/etc/nixos`).
- **Destination:** `/mnt/nix-backups` — the NFS automount from the
  Synology NAS (`192.168.1.30:/volume1/Backups/nix`, declared in
  `modules/computers/nixos.nix`; mounts on access, unmounts after 10 min
  idle, `nofail` so boot never hangs on the NAS).
- **Retention:** 7 daily, 4 weekly.
- **Passphrase:** the `borg-passphrase` agenix secret (declared once in
  `agenix.nix`), injected as the service's `EnvironmentFile` — the
  passphrase itself only exists encrypted in the repo + in 1Password via
  the `id_borg` recovery path.

**The NFS race, handled twice:** the `Persistent=true` timer can fire
during early boot, before the NFS automount is reachable or before DNS
is up. The borgmatic service therefore overrides home-manager's stock
`Restart = "no"` with `mkForce "on-failure"` + `RestartSec = "5min"` — a
failed run retries instead of silently losing the day's backup.

Restores are a first-class procedure, documented end-to-end in
[Restores (the borg view)](#restores-the-borg-view) below.

## Restores (the borg view)

`borg` is not on PATH — the wrapped copy rides inside borgmatic
(`borgmatic borg ...`, borg 1.4 syntax), and borgmatic intercepts the
repo-level subcommands it has native actions for (`borg list` → "try
`borgmatic list` instead"). Both layers read the same generated config
(`~/.config/borgmatic.d/nix-home.yaml`), so they need no arguments.
Expect the first command after an idle period to stall a few seconds
while the NFS automount pulls in `192.168.1.30`.

**Passphrase first.** The repo is `repokey BLAKE2b` — the key material
lives *inside* the repo on the NAS, so the passphrase alone decrypts
everything. In a running desktop session:

```console
$ export BORG_PASSPHRASE="$(sed 's/^BORG_PASSPHRASE=//' /run/user/$UID/agenix/borg-passphrase)"
```

(The agenix secret is a systemd `EnvironmentFile` — `KEY=value`, hence
the sed — and exists only while the session runs, since agenix
decrypts into per-session tmpfs. Anywhere else — a fresh install
before its first switch, or another box — read the passphrase from
1Password, the `id_borg` recovery entry
([identity](identity.md)).)

**Inventory.** Archive names are borgmatic's default
`{hostname}-{now}` — `nixos-` plus an ISO timestamp. Retention is
7 daily + 4 weekly, so the practical restore window is about a month;
anything older is pruned:

```console
$ borgmatic list                                            # archives
$ borgmatic list --archive nixos-2026-08-31T23:19:57.109469 # files in one
$ borgmatic info                                            # repo + archive stats
```

**Browse** without extracting — single archive over FUSE:

```console
$ mkdir -p /tmp/borg-mnt
$ borgmatic borg mount /mnt/nix-backups::nixos-2026-... /tmp/borg-mnt
$ ls /tmp/borg-mnt/home/batman/...
$ borgmatic borg umount /tmp/borg-mnt
```

**Extract.** Archive paths are relative (`home/batman/...`). Restore
into a scratch directory first and review before moving into place —
`--path` recreates the full prefix under the cwd:

```console
$ cd /tmp/restore
$ borgmatic extract --archive nixos-... --path home/batman/Documents --progress --list --dry-run
$ borgmatic extract --archive nixos-... --path home/batman/Documents --progress
$ rsync -avn home/batman/Documents/ ~/Documents/   # review, then drop -n
```

Whole-home disaster recovery is the same command with `--path
home/batman` from `/` — but on a fresh install follow the
[bootstrap](../bootstrap.md) order instead: the repo comes back via
git clone, `~/.ssh/id_borg` from 1Password, and one borg extract
covers the rest of `$HOME`. Two properties of the archive matter
there:

- **No excludes:** the whole home rides along — `~/.cache` included
  (5k+ entries; borg's dedup and zstd keep it cheap) — and with it
  `~/.ssh`, which holds the agenix identities: a restored home can
  decrypt its own secrets again.
- **The `/etc/nixos` source is vestigial:** it is a symlink into the
  home checkout (`/etc/nixos -> /home/batman/programming/nixos`), so
  the real config restore path is the checkout's GitHub remote —
  which the git timer keeps current daily.

**Integrity.** The generated config pins `checks: []` — borgmatic runs
no scheduled consistency checks, so a silently-corrupt repo would go
unnoticed between scrubs. Verify by hand after anything suspicious
(NAS hiccup, disk errors, a weird backup failure):

```console
$ borgmatic borg check --repository-only /mnt/nix-backups   # structural, cheap
$ borgmatic borg check --archives-only /mnt/nix-backups     # re-hashes everything, slow
```

To make checking routine instead, add a `checks` block to
`programs.borgmatic.backups.nix-home` in `batman/backup.nix`
(borgmatic then interleaves them with the nightly create/prune).

## git-backup (config)

A daily systemd **user** timer running `scripts/git-backup.sh` against
the `/etc/nixos` checkout. The script, in order:

1. Resolves the repo root from its own location (the script lives at
   `<repo>/scripts/git-backup.sh`); pass a different checkout path as
   `$1`.
2. **Exits 0 if the tree is clean** — `git diff --quiet && git diff
   --cached --quiet` plus no untracked files. A clean tree pushes
   nothing.
3. **Waits up to 5 minutes for DNS** (`getent hosts github.com`, 30 ×
   10 s) — the Persistent timer fires the moment the machine boots,
   possibly before the network is fully up.
4. `git add -A`, commit "Automated NixOS config backup".
5. `git pull --rebase --autostash` — another machine may have pushed in
   the meantime; rebase instead of failing the push on a diverged
   remote.
6. `git push` — over ssh with the dedicated `~/.ssh/git` key
   ([identity](identity.md)); the system-wide pre-trusted GitHub host
   key means it never blocks on a host-key prompt.

The **service** unit (not just the timer) also carries
`Restart = "on-failure"` + `RestartSec = "5min"` — the same boot-race
guard (systemd ≥ 254 allows Restart on `Type=oneshot`).

## Operational notes

- The timer commits and pushes **any dirty tree**, including a
  half-finished `nix flake update` — that is safe (CI eval-checks every
  push, including automated ones), but if you want a real commit
  message, commit before the timer fires (daily at midnight, plus
  immediately after any boot that missed a run).
- Both timers only exist on the desktop. The laptop and Mac keep their
  config in this repo by definition — there is nothing to back up
  locally.
- `repoPath` is bound once at the top of `backup.nix` — moving the
  checkout means changing that one line.
