# Laptop power (framework)

The framework's power/thermal stack lives in
`modules/computers/framework/_power.nix` (imported from
`framework.nix`). One platform fact drives most of it: **this is an
AMD board** — thermald is Intel-only (correctly absent), and the old
`hardware.framework` module is gone from this nixpkgs (checked
2026-09-06), its successor being `services.framework-control`.

## Charge ceiling

`charge_control_end_threshold = 80` — Framework's own battery-longevity
guidance. Applied by a boot oneshot and re-applied by a udev rule on
every `power_supply` change (dock/AC hotplug recreates sysfs state).
Raise to 100 (one number in the file) before an unplugged travel day;
the tradeoff is battery wear.

**Known gap (2026-09-05, framework on kernel 6.18):** BAT1 exposes no
`charge_control_end_threshold` sysfs file, so the oneshot is a
graceful no-op (`systemctl status framework-charge-threshold`
shows active, journal shows an instant clean exit). Next step when
it matters: the framework-control CLI sets the limit through the EC
directly — if the sysfs knob doesn't appear after a BIOS/fwupd
update, move the ceiling to a framework-tool invocation instead.

## Sleep

`mem_sleep_default=s2idle` pinned: `deep`/S3 is broken on AMD
Frameworks (resume failures), and s2idle is the kernel default — the
pin exists so the choice is deliberate and regressions (BIOS/kernel
updates shift sleep behavior; `fwupdmgr` in `system/hardware.nix` is
the other half of that fight) start from a known floor. Symptom to
watch: abnormal battery drain while suspended → check
`journalctl | grep -i suspend`, update BIOS via fwupd, re-measure.

## Lid close

`services.logind.lidSwitch = "suspend"` — logind's stock default,
stated explicitly because the two desktop sessions split the job:
under Plasma, powerdevil holds the handle-lid-switch inhibitor and
implements the lid itself (kscreenlocker locks on resume); under
Hyprland no daemon inhibits logind, so this line IS the lid handler
and hypridle (`batman/hyprland.nix`) supplies the lock-before-sleep
half via logind's PrepareForSleep — see
[Hyprland](hyprland.md#lock-before-sleep-hypridle). Docked keeps the
stock ignore (`lidSwitchDocked`): lid closed on a dock leaves the
external display alive.

## power-profiles-daemon

amd_pstate (kernel default on this Ryzen) is the driver;
power-profiles-daemon is its D-Bus profile layer — Plasma's battery
tray, `powerprofilesctl`, and framework-control all speak it. No TLP:
it asserts against p-p-d, and per-device tuning on a stock Framework
buys nothing.

## framework-control

Framework's own hardware daemon + CLI (fan curves, module LEDs, input
schemes) — shells out to `framework_tool`.

## Wifi MAC privacy

`system/wifi-privacy.nix` (base tier): NetworkManager
`wifi.cloned-mac-address = stable` — a different but consistent MAC
per SSID. Cross-network tracking via the hardware MAC dies; captive
portals and router-side device preferences keep working (unlike
`random`, which rotates per connection and trips hotel logins).
Mullvad covers the same concern at the network layer when the tunnel
is up; this covers every network the hardware joins. Known wrinkle:
the resolved resolver list (`system/dns.nix`) puts the LAN pihole
first, so off-LAN name resolution pays one timeout hop before
mullvad/quad9 answer — accepted for now (the pihole is the primary on
purpose).

## Rack-UPS watcher (`_ups.nix`)

The laptop is the fleet's only outage survivor (own battery), so it's
the only host that polls the Synology's NUT server (192.168.1.30:3493)
in real time — every 2 minutes, alerting on `OL→OB` and `OB→OL`
transitions only, silent when unreachable. See
[observability](observability.md) for the full UPS story (desktop =
forensics-only; the rack's shutdown choreography belongs to the
Synology).

## USBGuard — present but NOT enabled

`_usbguard.nix` is a policy template + runbook, deliberately
unimported: USBGuard blocks unmatched devices by default, and the
fingerprint reader/camera/audio sit on *internal* USB hubs — a blind
policy is a login lockout, not a config error CI can catch. The
runbook in that file's header: generate the policy ON the laptop
against its real devices, paste it in, then import the file. Threat
model: evil-maid USB while traveling.
