# Security

[← program notes](index.md) · modules: `sudo.nix`, `security.nix`, `nixos/base.nix` (sshd, known_hosts), `batman/ssh.nix`

## sudo-rs (`sudo.nix`)

`security.sudo-rs.enable = true` — sudo-rs (the Rust rewrite) replaces
classic sudo; the nixpkgs module disables `security.sudo` and asserts the
two never coexist. batman's `wheel` membership is declared once,
statically, in `modules/users.nix` — nothing to repeat here.

## paretosecurity (`security.nix`)

`services.paretosecurity.enable = true` with `trayIcon = false` — local
security-posture checks (disk encryption, firewall, updates, ...) run by
a system daemon, reported without a tray icon. Expect it to **flag the
missing disk encryption** — the desktop's root is plain btrfs, no LUKS
(see `_hardware.nix`). That finding is known and accepted.

## sshd (`nixos/base.nix`)

`services.openssh.enable = true` — the daemon is on, on every host that
eats the shared base. The module's `openFirewall` default opens port 22;
nothing else is opened (firewall otherwise default-deny). No password
auth tweaks — nixpkgs defaults (no root login, no password auth) apply.

## Pre-trusted GitHub host key

`programs.ssh.knownHosts."github.com"` pins the official
`ssh-ed25519` key (verified against <https://api.github.com/meta>) into
the **system-wide** `/etc/ssh/ssh_known_hosts`, which user ssh reads as
`GlobalKnownHostsFile`. Why: the daily
[git-backup timer](backup.md#git-backup-config) pushes unattended —
without the pin, a first-ever push would block forever on a host-key
prompt inside a non-interactive service.

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
