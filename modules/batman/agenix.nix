# modules/home/agenix.nix
{ inputs, ... }:

{
  users.batman.home.pc = { pkgs, config, ... }: {
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
      # instead (see importGpgKey below, cachix.nix, hypnotix.nix);
      # gpg-private-key is no longer registered for that reason.
      borg-passphrase = {
        file = ../../secrets/borg-passphrase.age;
        # systemd never expands ${...} in EnvironmentFile= — agenix's
        # default path is the literal "${XDG_RUNTIME_DIR}/agenix/
        # borg-passphrase", which systemd silently ignores (the
        # journal's "path is not absolute" warning), meaning borgmatic
        # ran WITHOUT BORG_PASSPHRASE. Force the evaluated absolute
        # path; agenix.service decrypts to this same option, so the
        # runtime location moves consistently.
        path = "/run/user/${toString config.home.uid}/agenix/borg-passphrase";
      };
      zai-api-key.file = ../../secrets/zai-api-key.age;
    };

    # Import the declaratively-delivered GPG key on first activation and
    # pin its ownertrust (6 = ultimate; --import-ownertrust is
    # idempotent), so a fresh system shows clean "good signature" checks
    # without any manual `gpg --edit-key` step. The .age is decrypted
    # inline (rage + id_borg, the identity bootstrap.md restores onto
    # /mnt before nixos-install) — NOT via the agenix runtime dir, which
    # does not exist yet during first-boot activation.
    home.activation.importGpgKey = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      if ! ${pkgs.gnupg}/bin/gpg --list-secret-keys BEB93A0F2837F4D1CCDDF341F3EB6A9821002B2C >/dev/null 2>&1; then
        ${pkgs.rage}/bin/rage -d -i ${config.home.homeDirectory}/.ssh/id_borg \
          ${../../secrets/gpg.age} | ${pkgs.gnupg}/bin/gpg --import
      fi
      # 6 = ultimate trust; --import-ownertrust is idempotent. GnuPG
      # >= 2.4 requires the full 40-char fingerprint here — the 16-char
      # key ID is rejected as "invalid fingerprint".
      printf '%s\n' 'BEB93A0F2837F4D1CCDDF341F3EB6A9821002B2C:6:' | ${pkgs.gnupg}/bin/gpg --import-ownertrust
      # Legacy cleanup: an earlier revision of this module left the
      # decrypted key at ~/.gnupg/private-key.asc (and it rode along in
      # the borg backup of $HOME). Remove it if still present.
      rm -f -- "${config.home.homeDirectory}/.gnupg/private-key.asc"
    '';
  };
}
