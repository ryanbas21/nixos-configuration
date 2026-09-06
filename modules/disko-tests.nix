# Disko layout round-trip tests: each host's `_disko.nix` is executed
# FOR REAL in a VM — partitioned, formatted, mounted (idempotency
# checked), a minimal NixOS installed onto it, and the result BOOTED as
# a second VM — then the live mounts of the booted machine are compared
# against the host's tracked mount table (`_hardware.nix` via
# nixosConfigurations). This is the labels contract as a test: a disk
# formatted by the layout satisfies the exact config bare metal runs.
#
# Reuses disko's own `makeDiskoTest` harness (tests/ in the locked
# disko input) rather than hand-rolling: it already knows how to shift
# the layout's device onto the VM's scratch disk (installer phase
# /dev/vdb; booted phase /dev/vda), build the format/mount/destroy
# scripts through the disko NixOS module (checkScripts on), install via
# switch-to-configuration into the ESP the layout just created, and
# boot the result. Upstream examples: disko's tests/*.nix.
#
# Scratch-disk sizing matters: `emptyDiskImages` defaults to 4G per
# disk in the harness, but the framework layout pins `end = "-67G"` for
# the root partition — sgdisk cannot place that end on a disk smaller
# than the swap it reserves, so framework gets an 80G *sparse* qcow2
# (qcow2 only allocates written blocks; the 67G swap partition is
# metadata-cheap). nixos/harmonia fit the 4G default.
#
# What each test proves, end to end:
# - the generated sgdisk/mkfs/btrfs-subvolume scripts run cleanly
#   (destroy,format,mount — twice, for idempotency);
# - the `framework-*`/`nixos-*`/`harmonia-*` PARTLABELs exist — the
#   symlinks _hardware.nix mounts through;
# - a system installed onto the layout BOOTs (systemd-boot into the
#   layout's own ESP) with every mount from `_hardware.nix` resolving:
#   device by partlabel, fsType, subvol (via FSROOT), fmask/dmask;
# - swap partitions are typed and mkswap'd where the layout has them.
{ config, lib, inputs, ... }:
let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  # disko's test harness, wired against the SAME locked nixpkgs (the
  # flake-level follows) — the defaults import <nixpkgs>, which is
  # impure/channel-dependent and would not exist in CI.
  diskoLib = pkgs.callPackage "${inputs.disko}/lib" {
    makeTest = import "${inputs.nixpkgs}/nixos/tests/make-test-python.nix";
    eval-config = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix";
    qemu-common = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix";
  };

  # host -> scratch-disk size in MiB (see header for why framework's
  # is 80G).
  hosts = {
    nixos = 4096;
    framework = 81920;
    harmonia = 4096;
  };
in
{
  flake.checks.x86_64-linux = lib.mapAttrs'
    (host: scratchMiB:
      lib.nameValuePair "disko:${host}" (
      let
        hostConfig = config.nixos.configurations.${host}.configuration.config;
        # The contract under test: everything _hardware.nix mounts from
        # the disk (partlabel devices only — NFS automounts are not
        # disk facts), plus its swap devices.
        expectedMounts = lib.filterAttrs
          (_: m: lib.hasPrefix "/dev/disk/by-partlabel/" m.device)
          (lib.mapAttrs
            (_: m: { inherit (m) device fsType options; })
            hostConfig.fileSystems);
        expectedSwap = map (s: s.device) hostConfig.swapDevices;
      in
      diskoLib.testLib.makeDiskoTest {
        inherit pkgs;
        name = "${host}-layout";
        disko-config = import ./computers/${host}/_disko.nix;
        extraInstallerConfig.virtualisation.emptyDiskImages =
          lib.mkForce [ scratchMiB ];
        # Runs after the install+boot phases, against the machine that
        # BOOTED from the disko-formatted disk: its mounts are the
        # layout's, at the real paths — compare them to the host's
        # tracked mount table.
        extraTestScript = ''
          import json

          expected = json.loads(r"""${builtins.toJSON expectedMounts}""")
          swaps = json.loads(r"""${builtins.toJSON expectedSwap}""")

          for mp, e in sorted(expected.items()):
              src = machine.succeed(f"findmnt -rn -o SOURCE {mp}").strip()
              real = machine.succeed(f"readlink -f {shlex.quote(e['device'])}").strip()
              # btrfs subvol mounts show as /dev/vdaN[/subvol]
              assert src.split("[")[0] == real, (mp, src, real)
              fst = machine.succeed(f"findmnt -rn -o FSTYPE {mp}").strip()
              assert fst == e["fsType"], (mp, fst, e["fsType"])
              opts = machine.succeed(f"findmnt -rn -o OPTIONS {mp}").strip().split(",")
              for opt in e["options"]:
                  # x-* are NixOS activation hints, never live options;
                  # defaults is implicit and absent from /proc mounts.
                  if opt.startswith("x-") or opt == "defaults":
                      continue
                  if opt.startswith("subvol="):
                      # host config says subvol=nix; live FSROOT is /nix
                      fsroot = machine.succeed(f"findmnt -rn -o FSROOT {mp}").strip()
                      want = "/" + opt.split("=", 1)[1].lstrip("/")
                      assert fsroot == want, (mp, fsroot, want)
                  else:
                      assert any(o == opt or o == "/" + opt for o in opts), (mp, opt, opts)

          for dev in swaps:
              real = machine.succeed(f"readlink -f {shlex.quote(dev)}").strip()
              out = machine.succeed(f"blkid {shlex.quote(real)}")
              assert 'TYPE="swap"' in out, (dev, out)
        '';
      }))
    hosts;
}
