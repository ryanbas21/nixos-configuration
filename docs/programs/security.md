# Security

[← program notes](index.md) · modules: `system/sudo.nix`, `system/security.nix`, `system/apparmor.nix`, `system/kernel-hardening.nix`, `system/network-hardening.nix`, `system/base.nix` (sshd, known_hosts), `batman/ssh.nix`

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
