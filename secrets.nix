let
  # The desktop's agenix identity (~/.ssh/id_borg). Decrypts every
  # secret. Its private half is backed up in 1Password, so losing the
  # machine and the NAS together still leaves a recovery path. (GitHub
  # pushes use a separate dedicated key, ~/.ssh/git — see
  # modules/batman/ssh.nix.)
  batman =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIELiz8KiOJ2x7L1J2yx3X8RZkZ3bd/uHcsUH5rzVw8Cl batman@nixos";
in
{
  # User-level secrets (home-manager agenix, identity ~/.ssh/id_borg).
  "secrets/borg-passphrase.age".publicKeys = [ batman ];
  "secrets/zai-api-key.age".publicKeys = [ batman ];
  "secrets/gpg.age".publicKeys = [ batman ];
}
