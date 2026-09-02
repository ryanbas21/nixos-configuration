# Virtualization

[← program notes](index.md) · module: `virtualization.nix`

## Docker: rootless + socket-activated system daemon

Two docker setups run side by side, on purpose:

- **`virtualisation.docker.enable = true` with `enableOnBoot = false`** —
  a *system* daemon that is **socket-activated**: it starts on the first
  docker command touching `/var/run/docker.sock`, not at boot. Nothing
  docker-related slows a boot; a month without docker means a month
  without the daemon running.
- **`virtualisation.docker.rootless`** with `setSocketVariable = true` —
  the user-level daemon for batman (no root for daily work);
  `setSocketVariable` exports `DOCKER_HOST` toward the rootless socket
  in the user's environment.

`users.users.batman.extraGroups = [ "docker" "vboxusers" ]` — added here
rather than in `users.nix`'s static declaration because membership is a
consequence of *this* feature, not of the account.

## VirtualBox host

`virtualisation.virtualbox.host.enable = true` — the host kernel modules
+ GUI tooling for running VMs. (If VirtualBox and the kvm-intel module
ever fight over a kernel upgrade, remember the kernel modules list also
comes from the tracked `_hardware.nix`.)

## Why this is in `nixos.modules.base` and not a "pc" tier

The repo's only NixOS host is this desktop, so the shared base has
nothing to distinguish from. The escape hatch, written down for the day
a second class of hosts appears: promote this to `nixos.modules.pc` —
declare the option with `mkModuleOption` and import it from each host
file that wants it (`modules/computers/<name>.nix`), same shape as
`nixos.modules.base`.
