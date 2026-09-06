# Program notes

[← docs](../../README.md)

One page per topic: what each program does, why it is there, and the
things that are not easy to remember. Files are grouped by the option
namespace they assign to (`home.base` reaches every machine;
`home.pc` is desktop-only; `nixos.modules.base` is the shared system
layer).

| Page | Module files | What it covers |
|---|---|---|
| [Neovim (nvf)](neovim.md) | `batman/nvf.nix`, `batman/_nvf/` | the nvf + dotfiles-lua bridge, the `_module.args` dance, known gaps |
| [Shell & CLI](shell-and-cli.md) | `batman/fish.nix`, `batman/fzf.nix`, `batman/packages.nix` | fish + plugins, fzf/fd, starship/zoxide/carapace/eza, direnv, package inventory |
| [Backups](backup.md) | `batman/backup.nix` | borgmatic to the NAS, boot-race retries, the retired git timer |
| [Nix caches](nix-caches.md) | `batman/cachix.nix`, `computers/harmonia.nix`, `system/base.nix` (settings), `lib.nix` | cachix + harmonia server (now a tracked host), substituter order, CI pushes, adoption runbook |
| [Disk layout (disko)](disko.md) | `disko.nix`, `computers/nixos/_disko.nix` | declarative partitioning, the labels contract, fresh-metal flow |
| [Maintenance](maintenance.md) | `system/maintenance.nix` | weekly GC, store optimisation, boot-entry caps — and why rollback reach is bounded |
| [DNS & time](dns-and-time.md) | `system/dns.nix`, `system/time.nix`, `system/base.nix` (tz) | resolved + DoT spelling gotcha, ntpd-rs, the Singapore timezone saga |
| [Security](security.md) | `system/sudo.nix`, `system/security.nix`, `system/base.nix` (sshd/known_hosts) | sudo-rs, paretosecurity, sshd, the pre-trusted GitHub host key |
| [Virtualization](virtualization.md) | `system/virtualization.nix` | rootless + socket-activated docker, VirtualBox |
| [Vicinae](vicinae.md) | `batman/vicinae.nix` | the launcher, setcap input server, desktop-entry shadow, raycast extensions |
| [Desktop apps](desktop-apps.md) | `batman/{ghostty,obsidian,kodi,hypnotix,screen-capture,time-of-day-gamma}.nix`, `system/base.nix` | Plasma/pipewire base, ghostty, kodi + hypnotix IPTV, obsidian, kooha, Night Light, 1Password |
| [Hyprland](hyprland.md) | `batman/hyprland.nix`, `system/base.nix` | the second Wayland session: xmonad keybinds, everforest rice, 0.56 gotchas, session daemons |
| [AI agents](agents.md) | `batman/agents.nix` | pi + llm-agents tools, model router, ZAI key flow |
| [Identity](identity.md) | `batman/{git,gh_cli,ssh,agenix}.nix` | git signing, GPG auto-import, SSH key inventory, gh |
