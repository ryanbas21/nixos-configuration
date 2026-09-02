#!/usr/bin/env bash
# One-time adoption of the harmonia cache server (192.168.1.82).
# Automates runbook steps 1-6, 8 and 9 (docs/programs/nix-caches.md,
# "Bringing .82 under management"); prints exactly what remains manual.
# Run on the desktop, in the repo checkout:
#   bash scripts/adopt-harmonia.sh
set -euo pipefail

REPO="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
cd "$REPO"
SSH="sudo ssh -o StrictHostKeyChecking=accept-new root@192.168.1.82"

echo "== 1. Box facts (platform, release, current stateVersion) =="
$SSH 'uname -m; nixos-version; grep -h "stateVersion" /etc/nixos/configuration.nix 2>/dev/null || true'
echo "    -> align system.stateVersion in modules/computers/harmonia.nix if it is not 26.05"

echo
echo "== 2. Current signing-key wiring (informational — the real key is"
echo "       already aged into secrets/harmonia-signing-key.age) =="
$SSH 'systemctl cat harmonia 2>/dev/null | grep -iE "SIGN_KEY|LoadCredential" | head -4' || true

echo
echo "== 3. Host key vs the keyscan'd recipient already in secrets.nix =="
HOST_PUB=$($SSH 'cat /etc/ssh/ssh_host_ed25519_key.pub')
echo "    $HOST_PUB"
if grep -q "$(echo "$HOST_PUB" | awk '{print $2}')" secrets.nix; then
  echo "    matches the harmonia recipient in secrets.nix — OK"
else
  echo "    MISMATCH — update the harmonia recipient in secrets.nix before deploying!"
fi

echo
echo "== 4. Every key currently authorized on the box =="
echo "    (paste any key beyond the desktop push key into authorizedKeys.keys too —"
echo "     the declarative assignment REPLACES the file on switch)"
$SSH 'cat ~/.ssh/authorized_keys'

echo
echo "== 5. The desktop push key (paste into users.users.root.openssh.authorizedKeys.keys"
echo "       in modules/computers/harmonia.nix — the eval assertion enforces it) =="
sudo cat /root/.ssh/id_ed25519.pub

echo
echo "== 6. Hardware scan -> modules/computers/harmonia/_hardware.nix =="
HW=$($SSH 'nixos-generate-config --show-hardware-config')
{
  echo "# Generated at first adoption from .82 via nixos-generate-config."
  echo "# Maintained by hand from here (see docs/machines.md, Hardware)."
  echo "$HW"
} > modules/computers/harmonia/_hardware.nix
echo "    written — review: git diff modules/computers/harmonia/_hardware.nix"
echo "    (the boot.loader lines now come from the box itself, replacing the placeholder)"

echo
echo "== REMAINING (manual, in order) =="
echo "  a. stateVersion per step 1, if it differs"
echo "  b. paste the step-5 push key (+ any step-4 extras) into computers/harmonia.nix"
echo "  c. commit + push (CI eval-checks the completed host — the assertion"
echo "     fails the check until the key list is non-empty)"
echo "  d. deploy: sudo nixos-rebuild switch --flake .#harmonia --target-host root@192.168.1.82"
echo "  e. verify: curl -s http://192.168.1.82:5000/nix-cache-info"
echo "             sudo nix copy --to ssh://root@192.168.1.82 /nix/store/<local-only path>"
echo "             curl -sf http://192.168.1.82:5000/<basename>.narinfo && echo PUSH WORKS"
