# DNS & time

[← program notes](index.md) · modules: `networking/dns.nix`, `time.nix`, `nixos/base.nix`

Small files, big gotchas.

## DNS (systemd-resolved)

`networking/dns.nix` configures resolved with an explicit server list,
LAN-first:

1. `192.168.1.39` — the pihole (ad-blocking for the whole LAN);
2. `extended.dns.mullvad.net` — mullvad's ad/tracker-blocking resolver;
3. `9.9.9.9` — quad9;
4. `1.0.0.1` + two IPv6 addresses — cloudflare.

`DNSOverTLS = "opportunistic"` — plaintext fallback allowed, since the
pihole is plain DNS on the LAN.

**The spelling gotcha (cost real debugging time):** systemd's gperf key
table — and therefore the NixOS option — is `DNSOverTLS`, **all caps**.
A differently-cased key is an unknown lvalue that resolved *silently
ignores*, leaving DoT at the module default `"false"`. If a resolved
setting ever seems to do nothing, check the casing first.

## Time sync (ntpd-rs)

`time.nix` enables `services.ntpd-rs` with log-level `warn`. Replaces
the default chronyd; nothing else configured — pool defaults apply.

## Timezone: static, and why (`America/Denver`)

The timezone is a static `time.timeZone = "America/Denver"` in
`nixos/base.nix`. It used to be dynamic — `automatic-timezoned` +
geoclue2 — and that entire chain was removed for a concrete reason:

> beacondb (the geoclue WiFi-geolocation backend) has zero WiFi
> coverage for this location, so every geolocate query falls back to
> IP-based lookup, and DB-IP misattributes this ISP's address to
> **Singapore** — putting the clock 14 hours off at every boot.

The same geolocation failure is why Night Light uses fixed coordinates
([desktop apps](desktop-apps.md#night-light-batmantime-of-day-gammanix)). If this machine ever
becomes mobile, revisit both — until then, static is correct.

Related history: while `automatic-timezoned` existed, its nixpkgs module
set `time.timeZone = null` on purpose and turned a static zone into an
**eval error** (a static zone would be silently overridden at runtime).
That constraint disappeared with the module; the static zone is now
unremarkable.
