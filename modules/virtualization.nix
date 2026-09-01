# Docker (system daemon + rootless) and VirtualBox host. Assigned to
# nixos.modules.base — the repo's only NixOS host is this desktop, so a
# separate "pc" tier has nothing to distinguish; if a second class of
# hosts appears, promote this to nixos.modules.pc (declare the option with
# mkModuleOption and import it in modules/computers/<name>.nix).
{ ... }:

{
  nixos.modules.base = {
    virtualisation = {
      docker = {
        enable = true;
        enableOnBoot = false;

        rootless = {
          enable = true;
          setSocketVariable = true;
        };
      };

      virtualbox.host.enable = true;
    };

    users.users.batman.extraGroups = [
      "docker"
      "vboxusers"
    ];
  };
}
