# modules/home/agenix.nix
{ inputs, ... }:

{
  users.batman.home.pc = { config, ... }: {
    imports = [
      inputs.agenix.homeManagerModules.default
    ];
    age.secrets.gpg-private-key = {
      file = ../../secrets/gpg.age;
      path = "${config.home.homeDirectory}/.gnupg/private-key.asc";
    };

    age.secrets = {
      borg-passphrase = {
        file = ../../secrets/borg-passphrase.age;
      };
      zai-api-key = {
        file = ../../secrets/zai-api-key.age;
      };
    };
  };
}

