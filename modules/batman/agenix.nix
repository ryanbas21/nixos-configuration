# modules/home/agenix.nix
{ inputs, ... }:

{
  users.batman.home.pc = { config, ... }: {
    imports = [
      inputs.agenix.homeManagerModules.default
    ];

    age.secrets = {
      borg-passphrase = {
        file = ../../secrets/borg-passphrase.age;
      };
    };
  };
}

