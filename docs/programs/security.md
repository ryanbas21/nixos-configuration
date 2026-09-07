# Security

[← program notes](index.md) · modules: `system/sudo.nix`, `system/security.nix`, `system/apparmor.nix`, `system/kernel-hardening.nix`, `system/network-hardening.nix`, `system/nix-access.nix`, `system/cups-hardening.nix`, `system/dns.nix` (llmnr), `system/base.nix` (sshd, known_hosts), `batman/ssh.nix`, `computers/framework/_usbguard.nix` (framework only)

## sudo-rs (`system/sudo.nix`)

`security.sudo-rs.enable = true` — sudo-rs (the Rust rewrite) replaces
classic sudo; the nixpkgs module disables `security.sudo` and asserts the
two never coexist. batman's `wheel` membership is declared once,
statically, in `modules/users.nix` — nothing to repeat here.

## paretosecurity (`system/security.nix`)

`services.paretosecurity.enable = true` with `trayIcon = false` — local
security-posture checks (disk encryption, firewall, updates, ...) run by
a system daemon, reported without a tray icon. Expect it to **flag the
missing disk encryption** — the desktop's root is plain btrfs, no LUKS
(see `_hardware.nix`). That finding is known and accepted. The RPC
check's port-111 finding is closed in config (2026-09-07): every NFS
mount is nfs4 and `services.rpcbind.enable = mkForce false` (the nfs
module turns rpcbind on unconditionally while
`boot.supportedFilesystems` includes nfs) — live-verified on the
framework (port 111 shut); lands on the desktop with its next switch.

## AppArmor beachhead (`system/apparmor.nix`)

`security.apparmor.enable = true` with **zero policies** — the LSM is
on the boot list, nothing is confined, nothing changes behavior.
Deliberate prerequisite: it clears the reboot-able LSM step out of the
way so per-app profiles can land later, one feature file each, every
one starting in **complain mode** (violations log to `journalctl -k`,
never block) and promoting to enforce only after a stable period —
the rollout pattern from ryan4yin/nix-config's `hardening/`. The VM
boot tests prove each step stays bootable. First candidates when the
time comes: the browser and the chat clients (Firefox, Signal,
Discord) — the apps that read the whole home today.

## Kernel module blacklist (`system/kernel-hardening.nix`)

`esp4`/`esp6` (IPsec ESP) and `rxrpc` (kAFS) are blacklisted **and**
stubbed with `install … /bin/false` — a plain blacklist stops manual
`modprobe` but a socket() with the right family can still autoload
the module; the stubs close that path. Zero users on this fleet (VPN
is WireGuard, no IPsec, no AFS), pure attack-surface removal —
Dirty-Frag-class LPEs have landed in exactly these forgotten modules.

## Kernel-image protection + sysctl floors (`system/kernel-hardening.nix`)

`security.protectKernelImage = true` — in **this** nixpkgs it does
exactly two things: `nohibernate` on the kernel command line and
`kernel.kexec_load_disabled` (a loaded kernel image can no longer be
swapped in without a reboot). Older folklore credits it kptr_restrict
and friends — this tree does not. `nohibernate` is free: sleep is
s2idle, never S4. Alongside it, the strong kernel values the fleet
was already running on (kptr_restrict 1, dmesg_restrict 1,
unprivileged_bpf_disabled 2, yama ptrace_scope 1,
perf_event_paranoid 2 — verified live 2026-09-07) are now **pinned**
in the repo: they were inherited kernel defaults, and an upstream
default change would have silently regressed them.

## Network sysctls (`system/network-hardening.nix`)

ICMP redirects die at both layers (`all` **and** `default`, v4+v6,
plus `secure_redirects` and `send_redirects`): the kernel takes the
max of the `all` and per-interface values, and interfaces created
after boot (every wlan association, docker bridges, VPN interfaces)
inherit `default` — which was permissive, so a host roaming onto
hostile wifi accepted redirects from it. Source routing stays pinned
off; `rp_filter` is deliberately **loose** (2) — martian sources drop,
asymmetric routing (docker bridges, Mullvad's fwmark tunnels)
survives; strict is one edit away. Martians log to the journal.

## Nix daemon ACL (`system/nix-access.nix`)

`nix.settings.allowed-users = [ "root" "@wheel" ]` (base tier) and
`[ "root" ]` on harmonia (`harmonia/_remote-builder.nix`). nixpkgs
defaults this to `["*"]` — any local uid could ask the daemon to
fetch and execute arbitrary derivations as nixbld. The fleet is
single-user: batman (wheel) + root are the only humans, and nothing
else invokes nix (post-build-hook runs inside nix-daemon; the
observability units never touch nix — verified 2026-09-07). Same
pin-don't-inherit move as sshd auth. `remotebuild` on harmonia is
explicitly NOT in the list — if the demotion ever happens, it must be
added or remote builds fail daemon auth (tripwire comment in place).
Prompted by [xeiaso.net/blog/paranoid-nixos-2021-07-18](https://xeiaso.net/blog/paranoid-nixos-2021-07-18/);
its impermanence/noexec ideas were considered and rejected (snapper
rollback is this fleet's philosophy; single-btrfs layout).

## systemd exposure sweep (2026-09-07)

The xeiaso article's `systemd-analyze security` sweep, run live on
the exposed daemons:

- **harmonia.service — 0.2 SAFE** (verified on the deployed box): the
  upstream module ships the full set (DynamicUser, SystemCallFilter,
  IPAddressDeny, ProtectSystem=strict, capability drops). Nothing to
  add.
- **sshd — 9.6, inherent**: privilege separation needs root +
  CAP_SETUID; unit-level sandboxing is not applicable. Its hardening
  is the key-only auth + LAN-scoped firewall + sysctl floors above.
- **cups.service — 9.2 → hardened** (`system/cups-hardening.nix`):
  localhost-bound and firewall-guarded, so the override is the safe
  subset only (NoNewPrivileges, PrivateTmp, kernel/home/namespace
  shields). CapabilityBoundingSet/@privileged syscalls and
  MemoryDenyWriteExecute are deliberately absent — they break cupsd's
  root→cups drop or the filter chain; the file header documents each.
- **LLMNR — listener killed** (`system/dns.nix`): resolved's default
  listens on `0.0.0.0:5355` on every link; `llmnr = "false"` with
  zero speakers on the fleet (no Windows, hosts addressed by IP/DNS).

## sshd (`system/base.nix`)

`services.openssh.enable = true` — the daemon is on, on every host that
eats the shared base. The module's `openFirewall` default opens port 22;
nothing else is opened (firewall otherwise default-deny). Auth is
**pinned, not inherited**: nixpkgs defaults `PermitRootLogin` to
`prohibit-password` but does *not* default `PasswordAuthentication` off
(upstream sshd ships yes — verified on the deployed harmonia box), so
the base closes both explicitly (`PasswordAuthentication = false`,
`KbdInteractiveAuthentication = false`): every host is key-only. This
matters most for the framework, which joins untrusted networks with
port 22 open.

## USBGuard (`computers/framework/_usbguard.nix`, framework only)

Allowlist-only USB policy against evil-maid / malicious-charger
attacks while traveling: implicit policy **blocks** anything not
matched by a rule, so the rules must cover every legitimate device —
including the internals (fingerprint reader, camera, keyboard, hubs)
whose absence would brick the PAM login path. The policy is
NixOS-managed (`services.usbguard.rules` → store-immutable);
nixpkgs's mutable `ruleFile` escape hatch (`usbguard allow-device -p`
appends without a rebuild) is deliberately not used — policy would
drift out of git, and this repo is the source of truth.

Gotcha that cost a debug session: usbguard requires rules at column
0; one indented line fails the WHOLE file with a misleading `:1:1
parse error` (Nix `''`-strings dedent only the shared minimum, so
lines pasted at mixed indentation keep leading spaces). The rules
are therefore a Nix list of per-device strings joined with
`builtins.concatStringsSep "\n"` — each element dedents
independently, making the trap structurally impossible.

Adding a device: plug it in, `just usbguard-add` (prints the
generated rule, appends it above the in-file marker, runtime-allows
until the rebuild), review `git diff`, `just rebuild framework`.
Device not at hand: hand-write a partial rule (`allow id 046d:c52b
name "..."`) — every omitted condition is a wildcard; tighten to
the hashed form once plugged. A trusted dock can be covered
wholesale with one `allow via-port "1-2"` rule (everything behind
that hub port) — a desk judgment call, never for hostile ports.

## Pre-trusted GitHub host key

`programs.ssh.knownHosts."github.com"` pins the official
`ssh-ed25519` key (verified against <https://api.github.com/meta>) into
the **system-wide** `/etc/ssh/ssh_known_hosts`, which user ssh reads as
`GlobalKnownHostsFile`. Why: non-interactive ssh to GitHub still
happens — the cachix activation hook's `gh secret set` sync
([nix caches](nix-caches.md)) runs before any interactive session
exists — and without the pin a first-ever push would block forever on
a host-key prompt inside it. (The daily git-backup timer that
originally justified the pin is gone; the hook kept the need alive.)

## SSH client (`batman/ssh.nix`, desktop-only)

Declares what previously lived in a hand-written `~/.ssh/config`:

- **GitHub auth is bound to `~/.ssh/git`**, the dedicated push key —
  deliberately *not* the agenix identity `id_borg` (one key, one
  purpose; the agenix identity never needs to leave the machine for
  routine pushes). `IdentitiesOnly = true` so ssh doesn't try every key
  in the agent against GitHub.
- `enableDefaultConfig = false` — opts out of home-manager's built-in
  `Host "*"` default block, which is deprecated and warns on every eval;
  the equivalent settings (no agent forwarding, no control master, etc.)
  are declared verbatim instead, per the `programs.ssh` deprecation
  notice.
- Home-manager backs any pre-existing manual `~/.ssh/config` up to
  `*.bak` on first activation (`backupFileExtension`).

The key inventory (who holds what, where the private halves are backed
up) lives in [bootstrap](../bootstrap.md#the-key-inventory-the-only-must-restore-items).
