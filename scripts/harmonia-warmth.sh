#!/usr/bin/env bash
# Cache-warmth probe: ask the LAN harmonia server which paths of a
# closure it can serve right now (HTTP 200 on the digest-only
# <hash>.narinfo — the substituter's exact request shape; full
# hash-name URLs 404 by protocol, see vm-test.nix's header). The
# day-to-day answer to "is the cache working?": a fresh LAN box can
# rebuild <closure> from .82 alone iff every path answers HIT. Full
# loop proven 2026-09-06 — docs/programs/nix-caches.md ("Verify"):
# 4033/4033 against /run/current-system.
#
# Usage — any nix installable or store path, default the running system
# (installables must already be realised: nix path-info cannot walk an
# unbuilt closure — 'nix build' it first, then probe the output path;
# store paths always work):
#   scripts/harmonia-warmth.sh
#   nix build /etc/nixos#nixosConfigurations.harmonia.config.system.build.toplevel
#   scripts/harmonia-warmth.sh ./result
# Env: HARMONIA_CACHE (default http://192.168.1.82:5000).
# Exit: 2 server unreachable · 1 a closure was unprobeable or served
# zero hits (the everything-404s failure mode, cf. the virtual-store
# note in modules/computers/harmonia.nix) · 0 otherwise.
set -euo pipefail

CACHE="${HARMONIA_CACHE:-http://192.168.1.82:5000}"

if ! curl -sf -m 5 -o /dev/null "$CACHE/nix-cache-info"; then
  echo "harmonia-warmth: $CACHE unreachable (nix-cache-info failed)" >&2
  exit 2
fi

if [ $# -eq 0 ]; then set -- /run/current-system; fi

hashes="$(mktemp)"
codes="$(mktemp)"
trap 'rm -f "$hashes" "$codes"' EXIT

cold=0
for closure in "$@"; do
  if ! nix path-info -r "$closure" \
      | while read -r p; do basename "$p" | cut -d- -f1; done \
      | sort -u > "$hashes"; then
    echo "harmonia-warmth: cannot inspect '$closure' — an installable must be" \
      "realised first ('nix build' it, then probe the output path);" \
      "store paths always work" >&2
    cold=1
    continue
  fi

  total="$(wc -l < "$hashes")"
  # curl prints one HTTP status per line; a -m timeout prints 000 and
  # exits nonzero, so xargs may return 123 — absorbed by || true.
  xargs -P 16 -I{} curl -s -m 3 -o /dev/null -w '%{http_code}\n' \
    "$CACHE/{}.narinfo" < "$hashes" > "$codes" || true

  # grep -c exits 1 on zero matches — absorb with || true.
  hits="$(grep -c '^200$' "$codes" || true)"
  misses="$(grep -c '^404$' "$codes" || true)"
  other="$(grep -c -v -e '^200$' -e '^404$' "$codes" || true)"

  pct=0
  if [ "$total" -gt 0 ]; then pct=$((100 * hits / total)); fi
  if [ "$total" -gt 0 ] && [ "$hits" -eq 0 ]; then cold=1; fi
  printf '%s\n  total %5d   HIT %5d (%3d%%)   MISS %5d   other %d\n' \
    "$closure" "$total" "$hits" "$pct" "$misses" "$other"
done

exit "$cold"
