# Vicinae

[← program notes](index.md) · module: `batman/vicinae.nix` · upstream docs: docs.vicinae.com/nixos

**Vicinae** (github:vicinaehq/vicinae) is a Qt desktop launcher — the
Spotlight/Raycast-style thing bound to the meta key. The flake provides
both a home-manager module and a NixOS module; this repo uses both, in
one feature file.

## The two halves

- **Home-manager side** (`users.batman.home.base`, gated
  `mkIf isLinux` — the flake only packages x86_64-linux): installs the
  package, writes settings to `~/.config/vicinae/nix.json`, and runs
  the daemon as a systemd user service under the graphical session
  (`systemd.enable = true`; `systemd.environment` can inject
  `USE_LAYER_SHELL=1` or `QT_SCALE_FACTOR` into launcher windows).
- **NixOS side** (`users.batman.nixos.base` — so it rides into the host
  via the host file's import of the user slot): the **input-server
  setcap wrapper**. Without it, clipboard/emoji pasting and snippets
  silently don't work — the input server needs privileges the flat user
  service can't have. It lives in the user's nixos slot rather than
  `nixos.modules.base` to keep it a batman-machine concern.

Import convention, same as nvf: the HM module import is unconditional
(imports must never reference module args — that recurses); only the
`programs.vicinae` assignment is gated on Linux.

## The desktop-entry shadow (crash-loop war story)

The package's menu entry runs `vicinae server --replace`, which
**SIGKILLs the unit-owned daemon** every time the icon is clicked — and
systemd's `Restart=always` reignites it. Happened twice (09:22 and
10:0x, in the logs). The fix: `xdg.desktopEntries.vicinae` shadows the
packaged entry under the same desktop ID with `exec = "vicinae open"` —
an IPC-only command that just opens a window against whatever daemon is
running. The shadow wins by XDG precedence
(`~/.local/share/applications/` beats the profile copy).

## Settings vs. in-app config

- Leaving `programs.vicinae.settings` unset = pure in-app config.
  Setting it writes `~/.config/vicinae/nix.json`, which **overrides**
  `settings.json`. Workflow for going declarative: tweak in-app, then
  copy from `~/.config/vicinae/settings.json` into the module.
- Extension config goes under
  `settings.providers."<entrypoint-id>"` — get the id from the
  installed-extensions menu → ctrl+k → "copy author and ID".
- **Secrets never go in settings** (world-readable store) — use
  `programs.vicinae.settingOverrides` with an agenix-generated file.

## Raycast-compatible extensions

Raycast-compat extensions build from the
github.com/raycast/extensions monorepo via the vicinae flake's
`mkRayCastExtension` (npm deps resolved by importNpmLock, so only the
repo fetch needs a hash). Currently: **1password** and
**homeassistant**, both pinned to a single monorepo rev. Bumping is
mechanical: change `raycastRev`, take the new hashes from the build
error, done.

Native vicinae extensions (from github.com/vicinaehq/extensions) would
need a second flake input — the exact lines are sketched in a comment
in `vicinae.nix`.

## Cache note

The vicinae input deliberately has **no `follows` on nixpkgs**: it
builds its package with gcc15Stdenv against its own nixpkgs, and a
follows would make `vicinae.cachix.org` miss, forcing a from-source
build on every bump (see [nix caches](nix-caches.md#substituter-order-desktop-modulesnixosbasenix)).
