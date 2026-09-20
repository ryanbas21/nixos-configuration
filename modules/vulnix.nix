# vulnix-scan: the wrapper CI's CVE scan job runs.
#
# Why a flake package invoked with `nix run` instead of a `checks`
# derivation: vulnix refreshes its cached NVD feed over the network on
# demand, and a sandboxed Nix build has no network — it can never be a
# check. CI (the `vulnix` job in .github/workflows/ci.yml) resolves each
# host's toplevel store path, then runs this wrapper with
# `-w security/vulnix-whitelist.toml <path>`.
#
# `-C` (vulnix --closure) is baked in on purpose: it scans the *runtime*
# closure of the given output path (`nix path-info -r`, outputs mapped to
# their derivers) instead of vulnix's default, which resolves the path to
# its .drv and walks the full *derivation* closure. That default drags in
# every build input — bootstrap toolchains (gcc 4.6, python 2.7, go
# bootstrap tarballs), fixed-output sources, vendored crates — none of
# which ship on the machines; on this fleet it roughly tripled the
# findings with build-time-only noise. Runtime-closure scanning matches
# what is actually deployed, and security/vulnix-whitelist.toml is
# triaged against exactly this mode (77 sections at last triage
# 2026-09-20; see docs/programs/security.md).
#
# LAN NVD warmth: before scanning, the wrapper copies the shared feed
# cache (harmonia's nginx on :8088 — modules/computers/harmonia/
# _vulnix-cache.nix) when the mirror's copy is newer than the local
# one (curl -z: nginx answers 304 for unchanged files, so warm checks
# are free). A cold machine then starts from a parsed ~190 MB ZODB
# instead of downloading+parsing ~2 GB of NIST feeds; vulnix's own
# staleness ladder still pulls the small `modified` delta from NIST
# when the shared copy is 2h–7d old. Unreachable mirror (off-LAN,
# GitHub runners — which set VULNIX_NVD_MIRROR="" for exactly this
# reason — or the server being down) falls through to vulnix's normal
# NIST path unchanged.
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.vulnix-scan = pkgs.writeShellApplication {
        name = "vulnix-scan";
        runtimeInputs = [
          pkgs.vulnix
          pkgs.curl
        ];
        text = ''
          mirror="''${VULNIX_NVD_MIRROR:-http://192.168.1.82:8088}"
          cache="''${VULNIX_CACHE_DIR:-''${HOME:-/tmp}/.cache/vulnix}"
          mkdir -p "$cache"
          # 304 (not newer) exits 0 with an empty body; only a real
          # body replaces the local cache. The stale .index is
          # dropped alongside — ZODB rebuilds it against the new file.
          if [ -n "$mirror" ] \
            && curl -sf --connect-timeout 2 --max-time 300 -z "$cache/Data.fs" \
                 -o "$cache/Data.fs.part" "$mirror/Data.fs" \
            && [ -s "$cache/Data.fs.part" ]; then
            mv -f "$cache/Data.fs.part" "$cache/Data.fs"
            rm -f "$cache/Data.fs.index"
          else
            rm -f "$cache/Data.fs.part"
          fi
          exec vulnix -C --cache-dir "$cache" "$@"
        '';
      };
    };
}
