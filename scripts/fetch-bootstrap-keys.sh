#!/usr/bin/env bash
# Automated variant of bootstrap runbook step 2: fetch the identity keys
# from a dedicated 1Password provisioning vault using a service-account
# token — no interactive sign-in, no key material in a terminal.
#
# 1Password side (one-time setup):
#   - a vault named "Provisioning" containing ONLY these three items,
#     each stored as a DOCUMENT (native SSH Key items don't export
#     faithfully through the CLI):
#       "bootstrap id_borg"  — the agenix identity (~/.ssh/id_borg)
#       "bootstrap git"      — the GitHub push key (~/.ssh/git)
#       "bootstrap harmonia" — the desktop /root push key (optional here)
#   - a service account with READ access to exactly that vault
#   - the token lives OFF the repo/CI — it is the carried bootstrap
#     secret; revoke/rotate it from the 1Password console at will
#
# Usage (on the ISO, after disko has mounted /mnt; or post-boot on any
# machine with nix, passing a different target):
#   export OP_SERVICE_ACCOUNT_TOKEN=ops_...
#   nix shell nixpkgs#_1password-cli -c \
#     bash scripts/fetch-bootstrap-keys.sh /mnt
set -euo pipefail

TARGET="${1:-/mnt}"
if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  echo "note: OP_SERVICE_ACCOUNT_TOKEN not set — using the current op session."
  echo "      Fine for validation on a signed-in desktop (biometric will prompt);"
  echo "      the headless ISO flow needs the service-account token."
fi
command -v op >/dev/null || { echo "op not found — run via: nix shell nixpkgs#_1password-cli -c bash $0 $TARGET"; exit 1; }

fetch() { # <document name> <output path>
  local name="$1" out="$2"
  mkdir -p -- "$(dirname "$out")"
  op document get "$name" --out-file "$out"
  chmod 600 "$out"
  # Validate the material is a real OpenSSH key before trusting it.
  if ssh-keygen -l -f "$out" >/dev/null 2>&1; then
    echo "  ok: $name -> $out ($(ssh-keygen -l -f "$out" | cut -d' ' -f1-3))"
  else
    echo "  ERROR: $out is not a parseable OpenSSH key — check the vault item '$name' (must be a Document holding the raw key file)"
    rm -f "$out"
    exit 1
  fi
}

echo "== fetching identity keys from the Provisioning vault =="
fetch "bootstrap id_borg" "$TARGET/home/batman/.ssh/id_borg"
fetch "bootstrap git"     "$TARGET/home/batman/.ssh/git"

# The /root harmonia push key only matters on the desktop flow; fetched
# to the target's /root for completeness when TARGET is /mnt.
if [ "$TARGET" = "/mnt" ]; then
  mkdir -p "$TARGET/root/.ssh"
  if op document get "bootstrap harmonia" --out-file "$TARGET/root/.ssh/id_ed25519" 2>/dev/null; then
    chmod 600 "$TARGET/root/.ssh/id_ed25519"
    echo "  ok: harmonia /root push key -> $TARGET/root/.ssh/id_ed25519"
  else
    echo "  note: no 'bootstrap harmonia' document — skipping the /root push key (optional)"
  fi
fi

echo
echo "Done. Post-install reminder: fix ownership if TARGET was /mnt:"
echo "  sudo nixos-enter -- chown -R batman: /home/batman/.ssh"
echo "Consider revoking/rotating the service-account token until the next reinstall."
