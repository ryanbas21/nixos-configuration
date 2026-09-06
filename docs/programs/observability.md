# Observability

The journal is write-only. smartd findings, scrub failures, GC
failures, a backup timer that stopped firing — everything that matters
lands in `journalctl` on a headless box or a lid-closed laptop that no
human opens. This is the layer that makes the fleet *push* its state
instead of waiting to be asked.

## Architecture

```
any host failure ──OnFailure──▶ notify-failed@.service ──POST──▶ the self-hosted ntfy
any host weekly  ──timer──────▶ health-digest.service ──POST──▶ (URL: agenix secret)
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
  `secrets/ntfy-url.age` (recipients in secrets.nix): a personal
  domain is not something the repo should broadcast. No publish auth
  today; if that changes, extend the secret's plaintext with a token
  line and teach the notify scripts to send it.
- **Client half** (`modules/system/observability.nix`, both the base
  tier and harmonia directly): the `notify-failed@` template, the
  digest service+timer, sysstat, and the journald cap. Scripts read
  the URL from `/run/agenix/ntfy-url` at runtime and no-op (journal
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

- **ntfy auth**: anonymous publish on the secret URL; if the server
  grows token auth, the secret gains a token line (see above).
- **healthchecks.io-style dead-man service**: the digest's
  stop-arriving-is-the-signal covers the same need without an external
  dependency.
- **Deploying our own ntfy**: the existing server wins — one thing to
  maintain, and it is already internet-reachable (roaming push for
  free); harmonia keeps its minimal cache-only posture.

## Verifying

```
ntfy app → server = the secret URL, topic = each hostname
sudo systemctl start health-digest      # a digest should arrive now
sudo systemctl start notify-failed@test.service   # synthetic failure push
journalctl -t observability             # delivery failures land here
```
