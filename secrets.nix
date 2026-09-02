let
  # The desktop's agenix identity (~/.ssh/id_borg). Decrypts every
  # secret. Its private half is backed up in 1Password, so losing the
  # machine and the NAS together still leaves a recovery path. (GitHub
  # pushes use a separate dedicated key, ~/.ssh/git — see
  # modules/batman/ssh.nix.)
  batman =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIELiz8KiOJ2x7L1J2yx3X8RZkZ3bd/uHcsUH5rzVw8Cl batman@nixos";

  # The harmonia cache server (192.168.1.82). Its agenix identity is
  # the ssh HOST key, so the server needs no user identity. Fetched via
  # `ssh-keyscan` from the LAN (trust-on-first-use, same posture as the
  # post-build-hook's accept-new); at adoption, verify it matches
  #   ssh root@192.168.1.82 'cat /etc/ssh/ssh_host_ed25519_key.pub'
  harmonia =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINtxzFwIX6e97M/y8aeL0qdI1lM7IykhxS49fe99c0b0 root@192.168.1.82";
in
{
  # User-level secrets (home-manager agenix, identity ~/.ssh/id_borg).
  "secrets/borg-passphrase.age".publicKeys = [ batman ];
  "secrets/zai-api-key.age".publicKeys = [ batman ];
  "secrets/gpg.age".publicKeys = [ batman ];

  # nix-configs cachix credentials. The signing key is the BARE secret
  # exactly as `cachix generate-keypair nix-configs` stores it in
  # cachix.dhall — NO `name:` prefix (a prefixed key fails server-side
  # signature verification; see modules/batman/cachix.nix).
  "secrets/cachix-auth-token.age".publicKeys = [ batman ];
  "secrets/cachix-signing-key.age".publicKeys = [ batman ];

  # The harmonia cache server's signing key: the secret half of the
  # nix-cache-1:... pair (modules/nixos/base.nix pins the public half).
  # System-level secret (modules/computers/harmonia.nix), encrypted to
  # both recipients: batman (so the desktop can edit it) and the
  # server's host key (so the box decrypts it at boot). Verified at
  # extraction — the derived public half matches the base.nix pin.
  "secrets/harmonia-signing-key.age".publicKeys = [ batman harmonia ];
}
