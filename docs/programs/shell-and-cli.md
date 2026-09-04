# Shell & CLI

[← program notes](index.md) · modules: `batman/fish.nix`, `batman/fzf.nix`, `batman/packages.nix`

## Fish

The interactive shell everywhere (also `users.defaultUserShell` on the
NixOS side). `fish.nix` assigns to `home.base`, so the desktop, laptop,
and Mac all get the identical shell bundle:

- **Plugins:** fzf-fish, autopair, sponge, done, colored-man-pages.
- **Abbreviations:** `gco` = `git checkout`; `ns` = `nix shell nixpkgs#`
  (which depends on `nixpkgs.flake.source` being set — that's what
  `modules/nixos/flake-source.nix` restores; see
  [architecture](../architecture.md)).
- **Environment set in `interactiveShellInit`:**
  - `fish_greeting` cleared;
  - `OP_BIOMETRIC_UNLOCK=true` — 1Password biometric unlock for its SSH
    agent;
  - `DEFAULT_USER` — hides the username segment in starship;
  - `ZAI_API_KEY` read from the agenix runtime dir, **guarded with
    `test -r`** so standalone machines (which carry no secrets) don't
    error on every shell.
- **fd is a hard dependency:** the fzf-fish plugin requires `fd` at
    runtime, so `fish.nix` installs it itself to stay self-contained.

**fzf-git.sh** (junegunn) keybindings (`Ctrl-G` prefixes) are closed over
from the `fzf-git-sh` flake input and dropped into
`~/.config/fish/conf.d/` — pinned, not packaged, because upstream ships
raw scripts.

## fzf

`fzf.nix` sets the default/file-widget command to
`fd --type f --strip-cwd-prefix --hidden --follow --exclude .git` —
hidden files included, `.git` excluded. One global workaround lives in
`modules/home.nix` (not here): `enableNushellIntegration = false`, forced
because the Intel Mac's nixpkgs-26.05-darwin ships fzf 0.72, one minor
below home-manager's 0.73 floor for the (default-on, unused-here)
nushell integration.

## The rest of the shell UX

| Tool | Why |
|---|---|
| starship | prompt (`catppuccin-mocha` in the terminal, `DEFAULT_USER` hides the user segment) |
| zoxide | `z` jumping |
| carapace | completion bridge for non-fish-native CLIs (fish integration on) |
| eza | `ls` replacement |
| direnv + nix-direnv | per-project environments; `use flake` support |

## Package inventory (`batman/packages.nix`)

Assigned to `home.base`, in two chunks: one everywhere-block plus a
single consolidated Linux-only block (one
`mkIf pkgs.stdenv.hostPlatform.isLinux`, per the gating convention
below):

- **Everywhere:** `fd`, `bat`, `xclip`, `cachix`, `ripgrep`.
- **Linux-only, with reasons:**
  - `agenix` CLI — built by the agenix flake input following unstable
    nixpkgs; unstable 26.11 dropped `x86_64-darwin`. Secrets are edited
    on the desktop, which also holds the agenix identity.
  - `ghostty`, `sshfs` — no `x86_64-darwin` package in nixpkgs.
  - `psysonic`, `rigup` — the former publishes no darwin packages; the
    latter's darwin output fails against unstable.
  - `lm_sensors`, `btop` — hardware monitoring.
  - `signal-desktop`, `discord` — messaging; `discord` is on the
    `unfreeNames` allowlist in `modules/lib.nix` (the Mac keeps no
    messaging apps from this repo). `kate` was dropped from the fleet
    entirely — the desktop no longer installs a GUI editor from here.
  - `1password-cli` — on the `unfreeNames` allowlist; on NixOS the
    setgid `op` wrapper from `modules/onepassword.nix` shadows any
    profile copy (`/run/wrappers/bin` precedes profiles in PATH), so
    this entry serves the standalone Linux laptop. The 1Password GUI
    itself is system-level, NixOS-only, and the Mac installs 1Password
    natively outside this repo ([machines](../machines.md)).
  - `gnumake`, `gcc`, `git` — build tools and git (the Mac relies on
    Xcode Command Line Tools for these).
- **From flake inputs:** `psysonic`, `rigup` (own nixpkgs pins).

The gating convention used here (and in nvf/vicinae/ghostty/agents):
check `pkgs.stdenv.hostPlatform` *inside* the home-manager module, never
in the `imports` list.

Where GUI apps live: ghostty's theme config is
[desktop apps](desktop-apps.md); the AI tooling (`pi`, `bun`, ...) is
[agents](agents.md).
