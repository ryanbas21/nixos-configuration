# Store maintenance (GC & boot entries)

[← program notes](index.md) · module: `maintenance.nix`

## What and why

Three guardrails against unbounded growth, on both NixOS hosts
(desktop + harmonia server):

| Setting | Effect |
|---|---|
| `nix.gc` automatic, weekly, `--delete-older-than 30d` | deletes generations older than 30 days — and their store paths, once nothing references them |
| `nix.settings.auto-optimise-store` | hardlinks identical store paths on write; dedup pays off fast under eval loops |
| `boot.loader.systemd-boot.configurationLimit = 10` | caps the boot menu at the 10 newest generations |

Why this landed when it did: the desktop had accumulated **2,397 system
generations and 109 ESP boot entries in ~5 days** of rebuild loops with
zero pruning configured — growth was strictly unbounded. Nothing had
broken yet only because the 498 GB root had 425 GB free.

## What one root timer covers

`nix-collect-garbage --delete-older-than` walks `/nix/var/nix/profiles`
recursively — that includes `per-user/batman`, where home-manager
generations live because of `useUserPackages`. So the single root timer
reclaims system **and** home generations; no separate
`home-manager expire-generations` dance.

Not covered: `~/.local/state/nix/profiles` (modern `nix profile`
installs). Nothing on the fleet uses them today; if that changes, a user
timer becomes necessary.

## Rollback interplay

These knobs bound rollback reach — deliberately, as one policy: you can
return to any generation from the last 30 days via
`nixos-rebuild switch --rollback`, and the boot menu offers the newest
10. The reasoning is in
[operations → rollback](../operations.md#rollback--failure-recovery);
with CI validating every push (including the backup timer's), and borg
covering data, older rollback points had negative value — they were only
filling disk.

## Which hosts, and how

The module assigns the same `retention` attrset twice: to
`nixos.modules.base` (the desktop eats the shared base) and directly to
`nixos.configurations.harmonia.module` — the server runs its own minimal
base but still gains a generation per remote `--target-host` deploy, so
it needs the same pruning. If a `nixos.modules.server` tier is ever
promoted out of the harmonia host file, fold the second assignment into
it.

## First run after deploying this

Expect a big one-time cleanup: the GC deletes ~2,300 generations of
dead store paths (run `nix path-info --all | wc -l` before/after if
curious — 61k paths at last count), and the **next rebuild** prunes the
ESP menu from 109 entries to 10. Subsequent weekly runs are boring.

Schedule check: `systemctl list-timers nix-gc.timer`.
