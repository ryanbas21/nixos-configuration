let
  batman =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIELiz8KiOJ2x7L1J2yx3X8RZkZ3bd/uHcsUH5rzVw8Cl batman@nixos";
in
{
  "secrets/borg-passphrase.age".publicKeys = [ batman ];
  "secrets/zai-api-key.age".publicKeys = [ batman ];
  "secrets/gpg.age".publicKeys = [ batman ];
}
