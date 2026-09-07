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
# triaged against exactly this mode (71 sections at last triage; see
# docs/programs/security.md).
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.vulnix-scan = pkgs.writeShellApplication {
        name = "vulnix-scan";
        runtimeInputs = [ pkgs.vulnix ];
        text = ''
          exec vulnix -C "$@"
        '';
      };
    };
}
