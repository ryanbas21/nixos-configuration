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
  # post-build-hook's accept-new); verified 2026-09-04 against the
  # box's /etc/ssh/ssh_host_ed25519_key.pub — key material identical,
  # only the comment field differs (root@nix-cache vs root@192.168.1.82).
  harmonia =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINtxzFwIX6e97M/y8aeL0qdI1lM7IykhxS49fe99c0b0 root@192.168.1.82";

  # The framework laptop's host key, read off the box itself
  # (/etc/ssh/ssh_host_ed25519_key.pub — comment says root@amd) 2026-09-06.
  framework-laptop =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBogygVOqZK4YBXOiHufygez1wsXQVbomtuowXlLtdFL root@amd";

  # The nixos desktop decrypts ntfy-url.age via id_borg, not its host
  # key: its host key could never be fetched ("nixos" does not resolve
  # from the laptop, nothing answered :22), so instead the desktop's
  # SYSTEM agenix offers /home/batman/.ssh/id_borg as an identity
  # (age.identityPaths in computers/nixos.nix) — the same recipient
  # every edit already uses. Resolved 2026-09-06.
in
{
  # User-level secrets (home-manager agenix, identity ~/.ssh/id_borg).
  "secrets/borg-passphrase.age".publicKeys = [ batman ];
  "secrets/zai-api-key.age".publicKeys = [ batman ];
  "secrets/gpg.age".publicKeys = [ batman ];

  # Hypnotix IPTV providers: the dconf GVariant text for
  # org.x.hypnotix/providers — xtream credentials are embedded in the
  # serialization, so the whole list ships encrypted and is applied at
  # activation by modules/batman/hypnotix.nix.
  "secrets/hypnotix-providers.age".publicKeys = [ batman ];

  # nix-configs cachix credentials. The signing key is the BARE secret
  # exactly as `cachix generate-keypair nix-configs` stores it in
  # cachix.dhall — NO `name:` prefix (a prefixed key fails server-side
  # signature verification; see modules/batman/cachix.nix).
  "secrets/cachix-auth-token.age".publicKeys = [ batman ];
  "secrets/cachix-signing-key.age".publicKeys = [ batman ];

  # The harmonia cache server's signing key: the secret half of the
  # nix-cache-1:... pair (modules/system/base.nix pins the public half).
  # System-level secret (modules/computers/harmonia.nix), encrypted to
  # both recipients: batman (so the desktop can edit it) and the
  # server's host key (so the box decrypts it at boot). Verified at
  # extraction — the derived public half matches the base.nix pin.
  "secrets/harmonia-signing-key.age".publicKeys = [ batman harmonia ];

  # The fleet's push-notification server URL: the pre-existing
  # self-hosted ntfy behind nginx. A personal domain name is not
  # something the repo should broadcast (scrapers correlate
  # repo ↔ infrastructure), so the URL itself is the secret — the
  # The server runs deny-all auth (2026-09-06: anonymous publish got
  # 40301), so the plaintext is TWO lines — the URL, then an access
  # token with write on the three host topics (the phone subscribes
  # with the same user's login). Scripts in system/observability.nix
  # and framework/_ups.nix read both at runtime from
  # /run/agenix/ntfy-url and no-op (journal note, never a failed unit)
  # when it is absent, which keeps the VM boot tests clean.
  "secrets/ntfy-url.age".publicKeys = [ batman harmonia framework-laptop ];
}
