# Observability

The journal is write-only. smartd findings, scrub failures, GC
failures, a backup timer that stopped firing — everything that matters
lands in `journalctl` on a headless box or a lid-closed laptop that no
human opens. This is the layer that makes the fleet *push* its state
instead of waiting to be asked.

## Architecture

```
any host failure ──OnFailure──▶ notify-failed@.service ──POST──▶ the self-hosted ntfy
any host weekly  ──timer──────▶ health-digest.service ──POST──▶ (URL+token: agenix secret)
                                              │
                                              ▼
                 phone (ntfy app) subscribes /<hostname> — anywhere, not just LAN
```

- **Server**: the pre-existing self-hosted ntfy behind nginx —
  deliberately NOT deployed by this repo (harmonia stays a pure cache
  server; no port, no service). Internet-reachable, so phones get
  instant push anywhere; the known trade is that the ntfy box does
  not ride the rack UPS — a mains event takes alerts down with
  everything else. The URL is the agenix secret
  `secrets/ntfy-url.age` (recipients in secrets.nix; plaintext = URL
  line + token line): a personal domain is not something the repo
  should broadcast. The server runs deny-all auth (since 2026-09-06):
  the fleet publishes with the token as a Bearer header and the phone
  subscribes logged in as the token's user — guessing a topic name
  grants nothing.
- **Client half** (`modules/system/observability.nix`, both the base
  tier and harmonia directly): the `notify-failed@` template, the
  digest service+timer, sysstat, and the journald cap. Scripts read
  the URL and token from `/run/agenix/ntfy-url` at runtime and no-op (journal
  note, never a failed unit) when it is absent — which is also what
  keeps the VM boot tests clean, where no secret can decrypt.

## Failure hooks

`notify-failed@.service` is a oneshot template that POSTs one urgent
push and can never itself fail (delivery errors degrade to the
journal — an alerting path that breaks the alerting unit would
recurse). Wired via `unitConfig.OnFailure`:

| unit | where | why not wired elsewhere |
|---|---|---|
| `nix-gc` | base + harmonia | |
| `fstrim` | base | harmonia is a virtio guest — no physical disk to trim |
| `snapper-timeline` / `-cleanup` | base | harmonia is ext4 |
| btrfs scrub | — (digest covers it) | its unit names are generated per-filesystem |
| borgmatic | — (digest covers it) | home-manager **user** unit; a system template can't see it |

## The weekly digest

Sunday 09:00 (`Persistent=true`, so a sleeping laptop pays its debt on
wake): uptime, failed units (system + batman's user manager, including
the borgmatic heartbeat), 7-day err-level journal count, filesystem
headroom (never poking the noauto NFS automounts awake), scrub status
and snapshot counts on btrfs hosts, the smartd overall verdict, and
the rack UPS state. Every section self-neutralizes on hosts that lack
the hardware, so one script serves all three NixOS boxes.

A host that stops posting digests is a host in trouble — the digest is
its own dead-man signal.

## Unit sandboxing

Both custom units run as root (they must — the OnFailure template and
the digest's `runuser` half), so they carry their own jail instead:
`systemd-analyze security --offline` scores `notify-failed@` at **2.0**
and `health-digest` at **2.7** (both “OK”, from the ~9.x of bare root).
The directive sets differ per unit, deliberately:

- `notify-failed@` gets the full strict set (strict ProtectSystem,
  PrivateDevices, empty CapabilityBoundingSet, `@system-service`
  syscall filter) — it needs only the network, the journal socket,
  and a read of the agenix secret.
- `health-digest` keeps the syscall filter and strict ProtectSystem
  but keeps the real `/dev/nvme0n1` (smartctl — so no PrivateDevices)
  and a `CAP_SETUID/SETGID/DAC_OVERRIDE` bounding set (`runuser -u
  batman` for the user-manager half of the digest).

Rollback rule if a directive ever breaks a run: delete that line, not
the block. The VM tests prove the units load and the system boots;
the first live firing after a switch (next Sunday digest, next unit
failure) is the exec proof — watch for it once.

## The rack UPS (Synology, NUT on 192.168.1.30:3493)

The UPS feeds the network rack only — router, switch, NAS, the
harmonia hypervisor. No NixOS host rides it, so there is no shutdown
choreography to wire: the rack's own shutdown-before-exhaustion is the
Synology's job (DSM's UPS support).

- **Desktop**: dies with mains, before any UPS event could reach it.
  Its outage story is already the config's (btrfs, `noauto` NFS
  automounts, persistent journald) plus one out-of-repo BIOS knob
  worth setting once: *restore AC power state = power on*, so an
  unattended outage ends with the desktop back up. UPS data on the
  desktop is forensics only — the digest's `ups (rack)` line answers
  "why did I reboot at 14:02".- **Laptop**: the fleet's only outage survivor on its own battery.
  `framework/_ups.nix` polls the Synology every 2 minutes and alerts
  on transitions only — `OB*` pages ("rack on battery, NAS on borrowed
  time"), back-to-`OL` notes the recovery. Unreachable (off-LAN, NAS
  down) is silent, not a false alarm.

## The rest of the file

- **earlyoom** (`system/oom.nix`, all hosts): zramSwap cushions a
  spike but kills nothing — earlyoom SIGTERMs the fattest process
  below ~10% free, so the browser dies instead of the session.
- **sysstat**: sar samples every 10 min — the after-the-fact "what
  happened at 3am" record (`sar -f /var/log/sa/...`).
- **journald cap**: `SystemMaxUse=1G` — the systemd default (10% of
  the btrfs root) is gigabytes nothing prunes.

## Decided against, for now

- **healthchecks.io-style dead-man service**: the digest's
  stop-arriving-is-the-signal covers the same need without an external
  dependency.
- **Deploying our own ntfy**: the existing server wins — one thing to
  maintain, and it is already internet-reachable (roaming push for
  free); harmonia keeps its minimal cache-only posture.

## Verifying

```
ntfy app → server = the secret URL, logged in as the token's user; topic = each hostname
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -d probe \
  -H "Authorization: Bearer $(sudo sed -n 2p /run/agenix/ntfy-url)" \
  "$(sudo sed -n 1p /run/agenix/ntfy-url)/$(uname -n)"   # expect 200
sudo systemctl start health-digest      # a digest should arrive now
sudo systemctl start notify-failed@test.service   # synthetic failure push
journalctl -t observability             # delivery failures land here
```
