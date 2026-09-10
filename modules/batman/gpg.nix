# GPG: declarative subkey-only signing. The private key material is
# delivered by the repo (secrets/gpg.age, agenix-encrypted to id_borg)
# and imported at home-manager activation — the same inline
# rage-decrypt pattern as cachix.nix/hypnotix.nix. The contract this
# file enforces: the PRIMARY key's secret never lives on a machine
# (only a gpg-agent stub does), so every signature a host produces —
# git commits included — comes from the signing SUBKEY. The real
# primary lives in 1Password. Long story: docs/programs/identity.md.
{ ... }:

{
  users.batman.home.pc = { config, pkgs, ... }: {
    # The .age file and fingerprint the activation hooks below
    # consume. The OPTIONS are declared in home-manager.nix's
    # sharedModules (home.pc is a deferredModule, which cannot carry
    # top-level `options`); this file assigns the real values, and the
    # fresh-boot VM tests (modules/vm-tests.nix) override them with
    # committed throwaway material — the REAL hooks run either way.
    activationSecrets.gpg.file = ../../secrets/gpg.age;
    activationSecrets.gpg.fingerprint = "BEB93A0F2837F4D1CCDDF341F3EB6A9821002B2C";

    programs.gpg = {
      enable = true;
      settings = {
        # Pin by full 40-char fingerprint (never the 16-char ID).
        # With the subkey-only keyring gpg RESOLVES this to the
        # signing subkey — the primary secret is a stub and cannot
        # sign even when named explicitly.
        default-key = config.activationSecrets.gpg.fingerprint;
      };
    };

    # Import the declaratively-delivered key on first activation and
    # pin its ownertrust (6 = ultimate; --import-ownertrust is
    # idempotent), so a fresh system shows clean "good signature"
    # checks without any manual `gpg --edit-key` step. The .age is
    # decrypted inline (rage + id_borg, the identity bootstrap.md
    # restores onto /mnt before nixos-install) — NOT via the agenix
    # runtime dir, which does not exist yet during first-boot
    # activation. gpg.age must contain `--export-secret-subkeys`
    # output (primary secret stubbed), NOT a full --export-secret-keys.
    home.activation.importGpgKey = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      if ! ${pkgs.gnupg}/bin/gpg --list-secret-keys ${config.activationSecrets.gpg.fingerprint} >/dev/null 2>&1; then
        ${pkgs.rage}/bin/rage -d -i ${config.home.homeDirectory}/.ssh/id_borg \
          ${config.activationSecrets.gpg.file} | ${pkgs.gnupg}/bin/gpg --import
      fi
      # 6 = ultimate trust; --import-ownertrust is idempotent. GnuPG
      # >= 2.4 requires the full 40-char fingerprint here — the 16-char
      # key ID is rejected as "invalid fingerprint".
      printf '%s\n' '${config.activationSecrets.gpg.fingerprint}:6:' | ${pkgs.gnupg}/bin/gpg --import-ownertrust
      # Legacy cleanup: an earlier revision of this module left the
      # decrypted key at ~/.gnupg/private-key.asc (and it rode along in
      # the borg backup of $HOME). Remove it if still present.
      rm -f -- "${config.home.homeDirectory}/.gnupg/private-key.asc"
    '';

    # Subkey-signing enforcement: the primary's secret key MATERIAL
    # must not exist on this machine — only a gpg-agent stub. In
    # `--with-colons` output the sec line's 15th field is '#' for a
    # stub and '+' for real material. Failing this aborts the switch,
    # so a mistaken full-key export inside gpg.age (or a manual
    # full-key import on any host) is caught at the next activation
    # instead of silently re-arming the primary across the fleet.
    home.activation.assertGpgSubkeyOnly = config.lib.dag.entryAfter [ "importGpgKey" ] ''
      flag="$(${pkgs.gnupg}/bin/gpg --list-secret-keys --with-colons ${config.activationSecrets.gpg.fingerprint} 2>/dev/null \
        | ${pkgs.gawk}/bin/awk -F: '$1=="sec" {print $15; exit}')"
      if [ "$flag" != "#" ]; then
        echo "gpg: primary secret key material is PRESENT (flag='$flag', expected stub '#')." >&2
        echo "gpg.age must hold gpg --export-secret-subkeys output; a locally imported full key must be" >&2
        echo "deleted (gpg --delete-secret-and-public-key ${config.activationSecrets.gpg.fingerprint}) before switching." >&2
        exit 1
      fi
    '';
  };
}
