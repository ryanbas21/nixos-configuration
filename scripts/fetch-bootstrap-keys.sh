#!/usr/bin/env bash
# Automated variant of bootstrap runbook step 2: fetch the identity keys
# from a dedicated 1Password provisioning vault using a service-account
# token — no interactive sign-in, no key material in a terminal.
#
# 1Password side (one-time setup):
#   - a vault named "Provisioning" containing ONLY the three identity
#     keys as SSH Key items — the natural shape. The script reads each
#     item's 'private key' field and validates every fetch with
#     ssh-keygen. A Document holding the raw key file is the byte-exact
#     fallback if an older CLI ever mangles the field export:
#       "bootstrap id_borg"  — the agenix identity (~/.ssh/id_borg)
#       "bootstrap git"      — the GitHub push key (~/.ssh/git)
#       "bootstrap harmonia" — the desktop /root push key (optional here)
#   - a service account with READ access to exactly that vault
#   - the token lives OFF the repo/CI — it is the carried bootstrap
#     secret; revoke/rotate it from the 1Password console at will.
#     Store it OUTSIDE the Provisioning vault: a token kept in the vault
#     it unlocks defeats rotation (a compromised token can read its own
#     replacement) and silently reaches every future vault item.
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

VAULT="Provisioning"

# SSH Key items first (the canonical shape — private key field);
# Documents as the byte-exact fallback (field export was lossy in
# op <= 2.13 — the ssh-keygen validation below catches any mangling
# from newer CLIs loudly instead of trusting it).
try_fetch() { # <item name> <output path>; rc 0 on success
  local name="$1" out="$2"
  mkdir -p -- "$(dirname "$out")"
  rm -f -- "$out"
  op read "op://${VAULT}/${name}/private key" --out-file "$out" 2>/dev/null && return 0
  op document get "$name" --out-file "$out" 2>/dev/null && return 0
  rm -f -- "$out"
  return 1
}

validate_key() { # <item name> <output path>
  local name="$1" out="$2"
  chmod 600 "$out"
  if ssh-keygen -l -f "$out" >/dev/null 2>&1; then
    echo "  ok: $name -> $out ($(ssh-keygen -l -f "$out" | cut -d' ' -f1-3))"
  else
    echo "  ERROR: $out is not a parseable OpenSSH key — the item '$name'"
    echo "  exported mangled (the known SSH-Key-item quirk) or holds wrong"
    echo "  material. A Document uploading the raw key file is byte-exact."
    rm -f -- "$out"
    exit 1
  fi
}

fetch() { # <item name> <output path> — required
  local name="$1" out="$2"
  if ! try_fetch "$name" "$out"; then
    echo "  ERROR: couldn't fetch '$name' as either a Document or an SSH Key"
    echo "  item (shapes: Document holding the key file, or SSH Key item read"
    echo "  via its 'private key' field; vault is expected to be '$VAULT')"
    exit 1
  fi
  validate_key "$name" "$out"
}

echo "== fetching identity keys from the Provisioning vault =="
fetch "bootstrap id_borg" "$TARGET/home/batman/.ssh/id_borg"
fetch "bootstrap git"     "$TARGET/home/batman/.ssh/git"

# The /root harmonia push key only matters on the desktop flow; fetched
# to the target's /root for completeness when TARGET is /mnt.
if [ "$TARGET" = "/mnt" ]; then
  mkdir -p "$TARGET/root/.ssh"
  if try_fetch "bootstrap harmonia" "$TARGET/root/.ssh/id_ed25519"; then
    validate_key "bootstrap harmonia" "$TARGET/root/.ssh/id_ed25519"
  else
    echo "  note: no usable 'bootstrap harmonia' item — skipping the /root push key (optional)"
  fi
fi

echo
echo "Done. Post-install reminder: fix ownership if TARGET was /mnt:"
echo "  sudo nixos-enter -- chown -R batman: /home/batman/.ssh"
echo "Consider revoking/rotating the service-account token until the next reinstall."
