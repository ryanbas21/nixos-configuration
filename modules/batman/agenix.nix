# modules/home/agenix.nix
{ inputs, ... }:

{
  users.batman.home.pc = { pkgs, config, ... }: {
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
    home.activation.importGpgKey = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      if ! ${pkgs.gnupg}/bin/gpg --list-secret-keys F3EB6A9821002B2C >/dev/null 2>&1; then
        ${pkgs.gnupg}/bin/gpg --import \
          ${config.age.secrets.gpg-private-key.path}
      fi
    '';
  };
}

