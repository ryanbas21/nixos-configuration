# The CI-side resurrection proof: boot the REAL harmonia host module
# (the exact module nixosConfigurations.harmonia deploys) as a UEFI
# QEMU guest and verify the cache server comes up serving SIGNED
# narinfos. This is the resurrection runbook's guarantee
# (docs/bootstrap.md) reduced to a flake check CI can run on every
# push — and since the harmonia host is itself a QEMU/KVM guest in
# production, the test boots the same virtualized reality, just on a
# runner's hypervisor instead of the LAN's.
#
# Overrides (everything else is the shipped config, verbatim):
# - fileSystems: the tracked _hardware mounts the physical box's
#   by-partlabel devices; the test framework supplies its own qcow2
#   (vda1 ESP / vda2 root under useEFIBoot), so the physical mounts
#   are force-replaced with the framework layout. systemd-boot and the
#   qemu-guest profile ride along unchanged from the host module.
# - signing key: the real one is age-encrypted to the physical box's
#   ssh host key, which a test VM does not have — so the age secret is
#   dropped entirely and a THROWAWAY key ships next to this file
#   (test-signing-key.nixkey; generated once with
#   `nix key generate-secret --key-name harmonia-test-1`, never used
#   for anything real). NIX format, base64 — NOT openssl PKCS#8 PEM:
#   harmonia rejects that with InvalidSigningKey "key is corrupt".
#   Public half, for the record:
#   harmonia-test-1:659xvzAKi/5hieOTssz904OM1RopzJFXuTfol+WQCas=
#
# Protocol note (cost several iterations to learn): the binary-cache
# protocol addresses narinfos by DIGEST ONLY — <32-char-hash>.narinfo,
# exactly what a substituter requests. A full <hash>-<name>.narinfo
# URL matches no route and 404s cleanly, looking exactly like a
# database problem (it isn't one; the earlier WAL-mode forensics in
# this saga were real but beside the point).
{ config, lib, inputs, ... }:
let
  hostModule = config.nixos.configurations.harmonia.module;
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  # The probe target: the harmonia package itself — guaranteed present
  # AND registered in the VM's nix db (ExecStart references it, so it
  # rides in the closure; note system.extraDependencies paths land in
  # the store but NOT in the registration manifest, so probing one of
  # those 404s too).
  probeHash = lib.strings.substring 0 32 (baseNameOf pkgs.harmonia);
in
{
  flake.checks.x86_64-linux."harmonia:vm-test" =
    pkgs.testers.runNixOSTest {
      name = "harmonia-vm-test";
      nodes.machine = { config, lib, pkgs, ... }: {
        imports = [ hostModule ];
        virtualisation.useEFIBoot = true;
        fileSystems = lib.mkForce {
          "/" = { device = "/dev/vda2"; fsType = "ext4"; };
          "/boot" = {
            device = "/dev/vda1";
            fsType = "vfat";
            options = [ "fmask=0022" "dmask=0022" ];
          };
        };
        services.harmonia.cache.signKeyPaths =
          lib.mkForce [ ./test-signing-key.nixkey ];
        age.secrets = lib.mkForce { };
      };
      testScript = ''
        machine.start()
        machine.wait_for_unit("multi-user.target")
        # harmonia is socket-activated; the socket listens at boot.
        machine.wait_for_open_port(5000)
        info = machine.succeed("curl -sf http://localhost:5000/nix-cache-info")
        assert "StoreDir: /nix/store" in info, info
        # The reproducibility proof: the box serves SIGNED narinfos for
        # its own store paths — digest-only URL (see header), response
        # signed by the committed test key specifically.
        code = machine.succeed(
          "curl -s -o /tmp/narinfo -w '%{http_code}' http://localhost:5000/${probeHash}.narinfo"
        ).strip()
        if code != "200":
          machine.succeed("journalctl -u harmonia.service --no-pager | tail -20 >&2 || true")
          raise Exception(
            "narinfo: HTTP " + code + ": " + machine.succeed("cat /tmp/narinfo")
          )
        narinfo = machine.succeed("cat /tmp/narinfo")
        assert "Sig: harmonia-test-1:" in narinfo, narinfo[:500]
      '';
    };
}
