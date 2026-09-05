{ config, ... }:

{
  nixos.configurations.framework = {
    module = {
      networking.hostName = "framework";

      system.stateVersion = "26.05";

      imports = [
        ./framework/_hardware.nix
        config.nixos.modules.base
        config.users.batman.nixos.base
      ];
    };
  };
}
