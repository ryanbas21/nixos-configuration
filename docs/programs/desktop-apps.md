# Desktop apps

[← program notes](index.md) · modules: `nixos/base.nix` (the desktop stack), `batman/{ghostty,obsidian,kodi,screen-capture,time-of-day-gamma}.nix`

## The system desktop stack (`nixos/base.nix`)

Host-agnostic, every NixOS host gets it:

| Piece | Notes |
|---|---|
| systemd-boot + EFI | `boot.loader.systemd-boot`; no GRUB |
| Plasma 6 + SDDM | `services.desktopManager.plasma6`, `services.displayManager.sddm` |
| X11 server | enabled (Plasma Wayland is the session, but X11 sits underneath for XWayland/X11 apps); keymap `us` |
| pipewire | full stack: alsa (+32-bit), pulse compat; `security.rtkit` for realtime; pulseaudio explicitly off |
| NetworkManager | networking; Wi-Fi state is machine state, not config |
| CUPS | printing enabled, no printer configured |
| Firefox | `programs.firefox.enable` |
| fish | `users.defaultUserShell` |
| `environment.profiles` | includes `$HOME/.nix-profile` + per-user profile, so `nix-env`-installed desktop entries/icons are visible |
| gnupg agent | with `enableSSHSupport` |
| locale | `en_US.UTF-8` everywhere (all LC_* pinned) |

## Per-app notes

### ghostty (`batman/ghostty.nix`)

Terminal, home.base but `mkIf isLinux` (no x86_64-darwin package).
Theme Catppuccin Frappe, font-size 12. Also installed as a package (see
[shell & CLI](shell-and-cli.md)).

### gammastep (`batman/time-of-day-gamma.nix`)

Day/night screen gamma, **desktop-only** (`home.pc`): GUI/Wayland-only.
`provider = "manual"` with **fixed Denver coordinates** (39.7392,
-104.9903) — not geoclue2. Why manual, in one breath: the geolocation
chain (geoclue → beacondb) has no WiFi coverage here and its IP fallback
places this ISP in Singapore, which put the sun schedule 14 hours off —
same root cause as the [static timezone](dns-and-time.md#timezone-static-and-why-americadenver).
Tray icon on. If the machine ever moves, update the coordinates.

### kodi (`batman/kodi.nix`)

Media center, desktop-only (`home.pc`) — kodiPackages are Linux-only and
the IPTV PVR setup belongs to the living-room box. Built with exactly
one addon: `pvr-iptvsimple`. Kodi's own settings/library are machine
state (data, not config).

### obsidian (`batman/obsidian.nix`)

Notes, desktop-only (`home.pc`) because the vault lives on the desktop.
One managed vault: target `Documents/Obsidian` (the vault *content* is
data — borgmatic covers it via `$HOME`). Declarative default settings:
`alwaysUpdateLinks`, `spellcheck`. Obsidian is on the `unfreeNames`
allowlist in `modules/lib.nix`.

### kooha (`batman/screen-capture.nix`)

Screen recorder, one line: `home.packages = [ pkgs.kooha ]`. Desktop-only
(`home.pc`): Wayland-native screen capture, no darwin package.

### 1Password

Both halves installed everywhere (home.base): `_1password-gui` +
`_1password-cli` (both unfree-allowlisted). Account sign-in is
interactive state. Fish sets `OP_BIOMETRIC_UNLOCK=true` for the SSH
agent biometric flow; the CLI (`op`) is used for scripting. See
[bootstrap](../bootstrap.md#fresh-desktop-runbook-same-hardware), step 6.

### xclip

Clipboard glue for X11 clients, installed everywhere.
