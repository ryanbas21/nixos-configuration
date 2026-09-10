# modules/home/agenix.nix
{ inputs, ... }:

{
  users.batman.home.pc = { ... }: {
    imports = [
      inputs.agenix.homeManagerModules.default
    ];

    age.secrets = {
      # Runtime-dir secrets only (decrypted by agenix's user service at
      # session start): borg-passphrase feeds borgmatic's EnvironmentFile,
      # zai-api-key is exported by fish. Activation-time consumers do NOT
      # read the runtime dir — agenix.service has no ordering guarantee
      # against home-manager activation, and with Linger=no it cannot run
      # before first login at all, so the runtime dir is empty during
      # first-boot activation. They decrypt inline with rage + id_borg
      # instead (see gpg.nix, cachix.nix, hypnotix.nix).
      borg-passphrase = {
        file = ../../secrets/borg-passphrase.age;
        # systemd never expands ${...} in EnvironmentFile= — agenix's
        # default path is the literal "${XDG_RUNTIME_DIR}/agenix/
        # borg-passphrase", which systemd silently ignores (the
        # journal's "path is not absolute" warning), meaning borgmatic
        # ran WITHOUT BORG_PASSPHRASE. The path must be a fully
        # evaluated absolute value: config.home.uid is EMPTY under
        # NixOS-integrated home-manager (uid not statically known —
        # "/run/user//agenix" killed both agenix.service and
        # borgmatic's env load), so pin batman's uid directly. 1000 is
        # the documented runtime dir (bootstrap.md, secrets.md); if the
        # uid ever changes, this moves with those docs. agenix.service
        # decrypts to this same option, so both sides stay in sync.
        path = "/run/user/1000/agenix/borg-passphrase";
      };
      zai-api-key.file = ../../secrets/zai-api-key.age;
    };
  };
}
