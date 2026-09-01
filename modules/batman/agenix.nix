# modules/home/agenix.nix
{ inputs, ... }:

{
  users.batman.home.pc = { pkgs, config, ... }: {
    imports = [
      inputs.agenix.homeManagerModules.default
    ];

    age.secrets = {
      # No custom `path` for gpg-private-key: the decrypted key stays in
      # agenix's per-session runtime dir (/run/user/<uid>/agenix, tmpfs)
      # instead of persisting on disk (and in the borg backup of $HOME).
      gpg-private-key.file = ../../secrets/gpg.age;
      borg-passphrase.file = ../../secrets/borg-passphrase.age;
      zai-api-key.file = ../../secrets/zai-api-key.age;
    };

    # Import the declaratively-delivered GPG key on first activation and
    # pin its ownertrust (6 = ultimate; --import-ownertrust is
    # idempotent), so a fresh system shows clean "good signature" checks
    # without any manual `gpg --edit-key` step.
    home.activation.importGpgKey = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      if ! ${pkgs.gnupg}/bin/gpg --list-secret-keys BEB93A0F2837F4D1CCDDF341F3EB6A9821002B2C >/dev/null 2>&1; then
        ${pkgs.gnupg}/bin/gpg --import \
          ${config.age.secrets.gpg-private-key.path}
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
