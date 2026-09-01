# Cachix integration: the nix-configs binary cache as repo state.
#
# CI (.github/workflows/ci.yml) pushes every path its build jobs create
# to the nix-configs cachix cache; the desktop and the Mac substitute
# from it (modules/nixos/base.nix on the NixOS side, the xdg.configFile
# below on the Mac). This file makes the cache's credentials part of the
# repository instead of machine state:
#
# - secrets/cachix-auth-token.age + secrets/cachix-signing-key.age hold
#   the cachix auth token and the BARE self-signing secret (the format
#   `cachix generate-keypair nix-configs` writes to cachix.dhall — no
#   `name:` prefix; a prefixed key fails server-side signature
#   verification, see the workflow comments for the war story).
# - On every desktop activation they are materialized into
#   ~/.config/cachix/cachix.dhall (fully derived: edit the .age files,
#   not the dhall) and synced to the repo's GitHub Actions secrets, so
#   CI's CACHIX_AUTH_TOKEN / CACHIX_SIGNING_KEY are provisions of this
#   repo, not state that exists only in GitHub's vault.
#
# Recovery story: a fresh machine needs only the agenix identity
# (~/.ssh/id_borg, private half in 1Password) — the first activation
# re-provisions the cachix CLI config and the CI secrets.
{ cachixCache, ... }:

{
  # Desktop: own the credentials, provision CLI + CI from them.
  users.batman.home.pc = { pkgs, config, ... }: {
    age.secrets = {
      # No custom `path` — decrypted into agenix's per-session tmpfs
      # runtime dir, never on disk (same convention as agenix.nix).
      cachix-auth-token.file = ../../secrets/cachix-auth-token.age;
      cachix-signing-key.file = ../../secrets/cachix-signing-key.age;
    };

    home.activation.provisionCachix = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      token="${config.age.secrets.cachix-auth-token.path}"
      key="${config.age.secrets.cachix-signing-key.path}"

      # ~/.config/cachix/cachix.dhall is derived state now. The file
      # the interactive `cachix authtoken` / `cachix generate-keypair`
      # flow once wrote by hand is rewritten from the repo's secrets on
      # every activation.
      tmp=$(${pkgs.coreutils}/bin/mktemp)
      printf '{ authToken =\n    "%s"\n, hostname = "https://cachix.org"\n, binaryCaches =\n  [ { name = "nix-configs"\n    , secretKey =\n        "%s"\n    }\n  ]\n}\n' \
        "$(cat "$token")" "$(cat "$key")" > "$tmp"
      ${pkgs.coreutils}/bin/install -D -m 600 "$tmp" "$HOME/.config/cachix/cachix.dhall"
      rm -f "$tmp"

      # Keep the GitHub Actions secrets in lockstep (CI authenticates
      # with the token and signs with the key). Best-effort with a LOUD
      # warning: a failed sync must not fail the switch, but it must
      # never be silent — silently stale CI secrets cost an evening
      # once already.
      for kv in "CACHIX_AUTH_TOKEN:$token" "CACHIX_SIGNING_KEY:$key"; do
        name="''${kv%%:*}"
        path="''${kv#*:}"
        if ! ${pkgs.gh}/bin/gh secret set "$name" -R ryanbas21/nixos-configuration < "$path"; then
          echo "WARNING: failed to sync $name to GitHub — CI cache pushes will fail until this succeeds (gh authenticated? network?)" >&2
        fi
      done
    '';
  };

  # Mac: own ~/.config/nix/nix.conf so the standalone home-manager
  # export substitutes from the cache. Single-user nix on macOS reads
  # the user config directly, so this is the whole story there.
  #
  # The CachyOS laptop is the one machine this cannot reach: its nix
  # daemon is root-owned and only /etc/nix/nix.conf counts — that entry
  # stays manual (the exact lines live in README, Hardware & deployment).
  users.batman.home.base = { lib, pkgs, ... }: {
    xdg.configFile."nix/nix.conf" = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      text = ''
        substituters = ${cachixCache.url} https://cache.nixos.org
        trusted-public-keys = ${cachixCache.publicKey} cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
        experimental-features = nix-command flakes
      '';
    };
  };
}
