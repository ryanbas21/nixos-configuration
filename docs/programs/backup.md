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

Restores: `borg list /mnt/nix-backups` / `borg extract` from the repo
path (see [bootstrap](../bootstrap.md#what-is-intentionally-not-reproducible)).

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
