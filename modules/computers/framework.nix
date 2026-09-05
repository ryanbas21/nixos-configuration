{ config, ... }:

{
  nixos.configurations.framework = {
    module = {
      networking.hostName = "framework";

      system.stateVersion = "26.05";
      services.fprintd.enable = true;

      imports = [
        ./framework/_hardware.nix
        ./framework/_pam.nix
        config.nixos.modules.base
        config.users.batman.nixos.base
      ];
    };
  };
}
