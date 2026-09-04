# Desktop apps

[← program notes](index.md) · modules: `nixos/base.nix` (the desktop stack), `batman/{ghostty,obsidian,kodi,screen-capture,time-of-day-gamma}.nix`

## The system desktop stack (`nixos/base.nix`)

Host-agnostic, every NixOS host gets it:

| Piece | Notes |
|---|---|
| systemd-boot + EFI | `boot.loader.systemd-boot`; no GRUB |
| Plasma 6 + SDDM | `services.desktopManager.plasma6`, `services.displayManager.sddm` |
| Hyprland | `programs.hyprland` — a second Wayland session in the SDDM picker (uwsm entry stripped); see [hyprland.md](hyprland.md) |
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

### Night Light (`batman/time-of-day-gamma.nix`)

Day/night screen temperature via **KWin's built-in Night Light**,
desktop-only (`home.pc`): GUI/Wayland-only. A previous incarnation ran
gammastep, which cannot drive Plasma Wayland at all — KWin implements
neither wlr-gamma-control nor a usable randr gamma path over XWayland
("SetCrtcGamma returned error 148"), so the indicator crash-looped
and notified about it ~twice a day. Two config files are involved:
`kwinrc` `[NightColor]` (the filter: DarkLight mode, 5500K day /
3700K night) and `knighttimerc` (the `knighttimed` schedule daemon
shared with automatic dark/light theming) — both edited in place by an
activation script (kwriteconfig6 + a KConfig notify D-Bus signal so a
running session applies them immediately), because they also hold
live Plasma state a whole-file replacement would clobber. The schedule
uses **fixed Denver coordinates** (39.7392, -104.9903) — not automatic
geolocation. Why manual, in one breath: the geolocation chain (geoclue
→ beacondb) has no WiFi coverage here and its IP fallback places this
ISP in Singapore, which put the sun schedule 14 hours off — same root
cause as the [static
timezone](dns-and-time.md#timezone-static-and-why-americadenver). If the
machine ever moves, update the coordinates. Under the [Hyprland
session](hyprland.md), gammastep runs instead (Hyprland implements
wlr-gamma-control, so the original tool works there) with the same
coordinates and temperatures, started per-session via exec-once.

### kodi (`batman/kodi.nix`)

Media center, desktop-only (`home.pc`) — kodiPackages are Linux-only and
the IPTV PVR setup belongs to the living-room box. Built with exactly
one addon: `pvr-iptvsimple`. Kodi's own settings/library are machine
state (data, not config).

### hypnotix (`batman/hypnotix.nix`)

IPTV player, desktop-only (`home.pc`) like kodi. The embedded mpv
renders into an X11 window (no Wayland surface), so under Hyprland it
runs via XWayland: the module's symlinkJoin wrapper forces
`GDK_BACKEND=x11`, and the declared dconf key
`org/x/hypnotix/mpv-options = "hwdec=auto-safe vo=x11"` carries the
upstream-recommended mpv flags for the same reason. The NixOS-side
assignment (`users.batman.nixos.base`) enables `programs.dconf` —
home-manager's dconf activation needs the D-Bus service or the
mpv-options write fails at activation time.

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

The desktop runs BOTH halves at the **system level**
(`modules/onepassword.nix`) because the CLI↔app integration is a
five-layer chain — each layer with its own failure signature, all
derived the hard way on 2026-09-02:

| # | Layer | Lives in | Failure signature without it |
|---|---|---|---|
| 1 | polkit policy with batman as owner | `programs._1password-gui` + `polkitPolicyOwners` | `PolicyKit daemon is not available` / handshake can't authenticate |
| 2 | the agent socket (`/run/user/<uid>/1Password/agent.sock`) | app toggle: Settings → Developer → **Use the SSH agent** | `connecting to desktop app: cannot connect` |
| 3 | the integration env var (current name) | fish: `OP_BIOMETRIC_UNLOCK_ENABLED` (the old `OP_BIOMETRIC_UNLOCK` is ignored) | integration silently off |
| 4 | socket peer-credential check | batman ∈ `onepassword` group | app log: `invalid group attempted to connect` → CLI sees `connection reset` |
| 5 | client-binary verification | `programs._1password` → setgid `onepassword-cli` wrapper at `/run/wrappers/bin/op` | `response: unsupportedClientType` |

Two field notes: `op whoami` *reports* sessions rather than initiating
them (a real command triggers the first authorization), and a stale
`~/.config/op/config` from any pre-integration `op account add` shadows
the app — `op account forget --all` clears it. The CLI package stays in
home.packages for the standalone exports; on the desktop the wrapper
wins via PATH order. Account sign-in is interactive state.

### xclip

Clipboard glue for X11 clients, installed everywhere.
