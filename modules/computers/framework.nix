{ config, ... }:

{
  nixos.configurations.amd = {
    module = {
      networking.hostName = "framework";

      system.stateVersion = "26.05";

      imports = [
        ./amd/_hardware.nix
        config.nixos.modules.base
        config.users.batman.nixos.base
      ];
    };
  };
}
