# Store maintenance (GC & boot entries)

[← program notes](index.md) · module: `system/maintenance.nix`

## What and why

Three guardrails against unbounded growth on the desktop-style hosts —
with one deliberate exception on the cache host (see
[below](#which-hosts-and-how)):

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

The module assigns twice: `nixos.modules.base` gets the full retention
set, collector included (the desktop-style hosts eat the shared base).
`nixos.configurations.harmonia.module` gets only the
optimise/boot-entry slice — **the cache host runs no `nix.gc`**.

Why the exception: every path in a binary cache is unreachable (that is
what being cached means), so any `nix-collect-garbage` — including
`--delete-older-than`, which gates *generations*, not the sweep —
treats the entire cache as garbage. Found live 2026-09-07: the box's
first weekly run after adoption deleted **7,304 paths / 38.4 GiB** of
pushed cache, and the desktop's next build re-pushed all of it over
the LAN. `harmonia.nix` carries an eval assertion keeping
`nix.gc.automatic` off, and the harmonia VM test asserts no collector
is active at boot. The box's disk guard is `nix.settings.min-free` in
`harmonia/_remote-builder.nix` — an in-daemon trigger that fires only
when the store disk is nearly full. If a `nixos.modules.server` tier
is ever promoted out of the harmonia host file, fold the second
assignment into it — carrying the no-GC rule with it.

## First run after deploying this

Expect a big one-time cleanup: the GC deletes ~2,300 generations of
dead store paths (run `nix path-info --all | wc -l` before/after if
curious — 61k paths at last count), and the **next rebuild** prunes the
ESP menu from 109 entries to 10. Subsequent weekly runs are boring.

Schedule check: `systemctl list-timers nix-gc.timer` (base hosts only —
harmonia has no collector by design).
