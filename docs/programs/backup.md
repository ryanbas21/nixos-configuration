# Backups

[← program notes](index.md) · modules: `batman/backup.nix`

NixOS hosts only: assigned to `home.pc`, not `home.base`, so the
standalone home-manager exports (CachyOS laptop, Mac) never inherit the
backup timer or the NFS-mount-dependent borgmatic config. Two halves:
data (borgmatic) and config (git itself — the repo is its own backup,
pushed by hand; the desktop's checkout also rides along in borg's
`$HOME` source).

## Borgmatic (data)

A daily user-level borgmatic run:

- **Sources:** `$HOME` (the whole home — no excludes) and the repo path
  (`repoPath` = `/etc/nixos`). On the desktop that path is a symlink
  into the home checkout at `~/programming/nixos` (so the home source
  is the real one); on the framework `/etc/nixos` **is** the checkout —
  a real directory — and is archived directly.
- **Destination:** `/mnt/nix-backups` — an NFS automount from the
  Synology NAS, declared per host in `modules/computers/<host>.nix`
  with an identical stanza shape (mounts on access, unmounts after
  10 min idle, `nofail` so boot never hangs on the NAS). The
  *export* differs per host: the desktop mounts
  `…:/volume1/Backups/nix` (whose root **is** its repo), the
  framework `…:/volume1/Backups/nix-laptops` — a dedicated export,
  because borg refuses to create a repository inside another
  repository's tree ("A repository already exists at <parent>",
  learned 2026-09-05 when the framework first tried `nix/framework`
  beside the desktop's repo files).
- **One repo per host:** the desktop predates the fleet, so its repo
  lives at the share *root* (`/mnt/nix-backups`, archive prefix
  `nixos-`); every other host gets its own subdirectory
  (`/mnt/nix-backups/<hostname>` — the framework's, archive prefix
  `framework-`). Separate repos mean no cross-host borg locking over
  NFS and independent retention. `backup.nix` branches on
  `osConfig.networking.hostName`; do not "fix" the desktop onto a
  subdirectory — that would orphan its existing repo and dedup
  history.
- **Retention:** 7 daily, 4 weekly.
- **Passphrase:** the `borg-passphrase` agenix secret (declared once in
  `agenix.nix`), injected as the service's `EnvironmentFile` — the
  passphrase itself only exists encrypted in the repo + in 1Password via
  the `id_borg` recovery path.
- **On battery:** home-manager's borgmatic module hard-codes
  `ConditionACPower=true`, which silently skips every run on a laptop
  on battery (the framework's first weeks looked backed up but never
  ran — timer green, service skipped). `backup.nix` therefore forces
  the condition to `false` everywhere except the desktop
  (`hostName == "nixos"`): battery hosts back up regardless; a daily
  incremental is minutes and `systemd-inhibit` keeps sleep from
  interrupting it. On the always-on-AC desktop the value is unchanged.

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
`{hostname}-{now}` — `nixos-` or `framework-` plus an ISO timestamp,
each inside its own repo (so `borgmatic list` on a host shows only that
host's archives). Retention is
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

## The config half: git, by hand

Config used to have an automated half — a daily user timer
(`scripts/git-backup.sh`, now deleted) that committed any dirty tree as
"Automated NixOS config backup" and pushed it. It was retired:
hand-made commits carry real messages, and they now pass through the
pre-commit hook (`modules/pre-commit.nix`, git-hooks.nix + deadnix) —
declared in this very repo, so `nix develop` installs it. A dirty tree
is simply your responsibility to commit when it's ready; borg still
snapshots the working tree daily regardless, so nothing is lost if a
day slips.

## Operational notes

- The timer exists on every NixOS host (desktop + framework). The
  CachyOS laptop and Mac keep their config in this repo by definition —
  there is nothing to back up locally.
- `repoPath` is bound once at the top of `backup.nix` — moving the
  checkout means changing that one line.

## Bringing a new NixOS host into backups

The config side is declarative: give the host an NFS automount stanza
modeled on `modules/computers/nixos.nix`, pointed at **its own export**
(not inside any existing host's repo — see the nesting note above),
and `backup.nix` picks the `<hostname>` subdirectory repo up
automatically. The repo itself is **not** auto-created — borgmatic 2.x
has no auto-init during `create` — so run, once, from the new host:

```console
$ ls /mnt/nix-backups/          # pull the automount in
$ export BORG_PASSPHRASE="$(sed 's/^BORG_PASSPHRASE=//' /run/user/$UID/agenix/borg-passphrase)"
$ borgmatic repo-create -e repokey-blake2
$ borgmatic create --stats      # the first, full backup
```

Do this **before** the first `nixos-rebuild switch` that carries the
borgmatic unit changes, as belt-and-suspenders: sd-switch normally
leaves an idle timer-driven oneshot alone (it only stop-starts units
that are active or auto-restarting mid-switch, and the unit's
`X-SwitchMethod=keep-old` — see `backup.nix` — exempts it even then),
but a seeded repo plus one completed backup means any early run is a
fast incremental instead of a first full sync. On the framework the
one-time cutover mounted the share by hand (`sudo mount -t nfs
192.168.1.30:/volume1/Backups/nix /mnt/nix-backups`) before the
automount unit existed, then unmounted before the switch so systemd's
own automount takes over cleanly.
