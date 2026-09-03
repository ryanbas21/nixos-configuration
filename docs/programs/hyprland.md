# Hyprland

[← program notes](index.md) · modules: `nixos/base.nix` (session enable), `batman/hyprland.nix` (everything else)

**Hyprland as a second Wayland session next to Plasma.** SDDM gets a
session picker entry; nothing is forced, Plasma stays the default. The
design brief was "hyprland like my xmonad": keybinds and layout habits
come from the xmonad config in the dotfiles repo (flake input
`ryan-nvim`), the look comes from the
[summer-day-and-night](https://github.com/MathisP75/summer-day-and-night)
rice (flake input `summer-day-and-night` — everforest dark, used for
the wallpaper and the palette; its config files are ported into Nix,
not consumed raw).

## The two files

- **`nixos/base.nix`**: `programs.hyprland.enable` (session file,
  portal, security wrapper) plus the uwsm-session strip below.
- **`batman/hyprland.nix`** (`home.pc`, desktop-only): the compositor
  settings, keybinds, window rules, and the whole session stack —
  waybar, wofi, dunst, hyprpaper, hyprlock, gammastep, grim/slurp
  screenshots, clipboard history.

## The uwsm session (black-screen war story)

The hyprland package ships a `hyprland-uwsm.desktop` ("Hyprland
(uwsm-managed)") in `share/wayland-sessions/` **unconditionally**, but
the NixOS module only wires uwsm itself up under `withUWSM = true`.
Picking that entry on first boot black-screened: the Exec's uwsm
exists in the closure, its session units don't. Building with
`withSystemd = false` would drop the file but also Hyprland's systemd
integration, so instead `programs.hyprland.package` is a `symlinkJoin`
relink of the stock package minus that one file (no hyprland rebuild),
with passthru `version`/`override`/`meta.mainProgram` restored — the
module's `genFinalPackage` and `security.wrappers` probe all three
(`functionArgs pkg.override`, `versionOlder cfg.package.version`,
`getExe`).

## 0.56 gotchas (the Lua-config era)

Hyprland 0.56 (nixpkgs unstable, 26.11) grew a Lua config backend, and
home-manager flips its default to render `hyprland.lua` for
stateVersion ≥ 26.05. This config pins
`wayland.windowManager.hyprland.configType = "hyprlang"`:

- the classic format is still fully supported;
- the `$variable` idiom (palette + `$mainMod`, hoisted to the top of
  the conf by the module's `importantPrefixes`) only exists in
  hyprlang — the Lua renderer turns `"$bg0"` keys into literally
  `hl.$bg0(...)`, which isn't even parseable Lua;
- the rice and most wiki examples are hyprlang.

Renamed/removed options hit on first boot, all verified against the
live compositor via `hyprctl keyword`:

| Old | 0.56 status | Replacement |
|---|---|---|
| `focusmaster` dispatcher | removed | `layoutmsg, focusmaster` (master layout still answers it) |
| `master:new_is_master` (bool) | renamed | `master:new_status = "master"/"slave"` |
| `dwindle:pseudotile` | removed | — (the `pseudo` dispatcher went with it) |
| `gestures:workspace_swipe` | removed | gesture API, Lua-config-only; no touchpad here, dropped |
| `layerrule noanim, <ns>` | syntax changed | field/value pairs (`no_anim 1`); the namespace-match spelling is undiscoverable offline — rule dropped (was cosmetic) |
| hyprpaper `preload`/`wallpaper = ,path` | removed in 0.8's hyprtoolkit rewrite | `wallpaper { monitor =; fit_mode = cover; path = ... }` blocks (empty monitor is still the wildcard) |

Also in 0.56: a Windows-style **"Go to settings to activate Hyprland"
donation nag** painted over the wallpaper until
`ecosystem.no_donation_nag = true` (the documented off switch), and
built-in mascot wallpapers that show whenever nothing else claims the
background — `misc.force_default_wallpaper = 0` +
`disable_hyprland_logo = true` are belt-and-braces behind hyprpaper.

## Session daemons: exec-once, not home-manager services

Waybar, dunst, hyprpaper, and gammastep are started by `exec-once`,
deliberately **not** via HM systemd services: those bind to
`graphical-session.target`, which also activates inside the Plasma
session — dunst would fight Plasma's notification daemon, and
gammastep cannot drive KWin at all (see
[desktop-apps.md](desktop-apps.md) for that saga). exec-once scopes
them to Hyprland only.

Related trap: **config files don't install binaries.** The first cut
of this module wrote dunst/hyprpaper/gammastep configs via
`xdg.configFile` but never added the packages, so the exec-once lines
died with command-not-found — no wallpaper, notifications, or gamma,
and Hyprland's mascot fallback underneath the nag. All three live in
`home.packages` now.

gammastep is the deliberate exception to the KWin Night Light story:
under Hyprland it works again (Hyprland implements
wlr-gamma-control), so the session runs the same Denver 5500/3700 K
schedule the Plasma session gets from Night Light.

## The keymap (xmonad translation)

`$mainMod = SUPER` — Hyprland's convention; xmonad used mod1Mask/ALT,
but the chords are identical apart from the modifier and SUPER leaves
Alt free for terminal shortcuts. The shape: SUPER+Return ghostty,
SUPER+Space launcher, SUPER+Tab window switcher (wofi), SUPER+J/K
cycle the stack, SUPER+M focus master, SUPER+H/L shrink/grow the
master split (mfact), SUPER+comma/period add/remove masters,
SUPER+[/] cycle workspaces, SUPER+Shift+1..0 move-without-follow,
SUPER+F fullscreen, SUPER+W tabbed groups (xmonad's "Tabbed
Simplest"), SUPER+E flips master↔dwindle (a store script), SUPER+R
resize submap, SUPER+G toggles the bar (xmonad ToggleStruts),
SUPER+Shift+X hyprlock, SUPER+Shift+P power menu, F12/Shift+F12
grim+slurp region/full screenshots. Master layout first, mfact 0.67,
gaps 20/6 — the xmonad numbers.

One deliberate deviation: xmonad had fullscreen on M-f and the browser
on M4-f — different mods, same physical key. On a single SUPER mod
they collide; fullscreen keeps F, firefox takes **SUPER+B**.

Firefox auto-rules to workspace 2 (the xmonad ManageHook), pavucontrol
and friends float.

## Vicinae is the launcher

[Vicinae](vicinae.md) is bound to SUPER+Space (`vicinae open` against
the daemon its own module already runs), plus float+center window
rules so the tiler doesn't adopt the popup — see `windowruleV2` in the
module. Wofi stays for the window switcher and the power menu.

## The glyph helper

Waybar icons, the power-menu entries, and friends use FontAwesome
private-use codepoints from JetBrainsMono Nerd Font. PUA characters
are easy to lose in editor/tooling transit — the first cut of this
module shipped `"format": ""` for the waybar power button, which
waybar renders as an absent module (an invisible button). Glyphs are
therefore written as ASCII JSON `\u` escapes and decoded by a Nix
helper:

```nix
glyph = code: builtins.fromJSON ''"\u${code}"'';
```

## Rice deltas vs summer-day-and-night

Kept: everforest dark palette (single Nix attrset feeds hypr, hyprlock,
waybar, wofi, dunst), border/rounding/shadow geometry, the accent
underline bar. Dropped: the day/night theme switcher (live-seds VS
Code/Obsidian/Firefox state — fights a declarative repo), the patched
3D border effect (needs a Hyprland source patch), kitty (ghostty is
the terminal), SUPER-mod binds (replaced by the xmonad translation).
