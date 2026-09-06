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
# Scratch-disk sizing: `emptyDiskImages` defaults to 4G per disk in
# the harness, which every layout now fits — the framework layout's
# old `end = "-67G"` root (reserving a 67G swap partition) used to
# demand an 80G sparse qcow2; the LUKS rework dropped the swap
# (zramSwap + earlyoom are the deliberate memory story), and a 100%
# root formats fine in 4G.
#
# What each test proves, end to end:
# - the generated sgdisk/mkfs/btrfs-subvolume/luksFormat scripts run
#   cleanly (destroy,format,mount — twice, for idempotency);
# - the `framework-*`/`nixos-*`/`harmonia-*` PARTLABELs exist — the
#   symlinks _hardware.nix addresses (the LUKS device by partition,
#   the btrfs through /dev/mapper/cryptroot);
# - the framework's/nixos's root partitions ARE LUKS2 containers
#   (isLuks) and the booted systems hold them open as `cryptroot` — the format phase
#   unlocked with the harness-seeded /tmp/secret.key (disko
#   lib/tests.nix), the exact file the bare-metal runbook in _disko.nix
#   creates for luksFormat; the BOOT phase unlocks with the same file
#   seeded into the initrd (extraSystemConfig below), standing in for
#   the TPM-sealed slot that does this job on metal — a QEMU guest has
#   no TPM device, so tpm2-device=auto would fall through to a prompt
#   there; same crypttab entry, second credential;
# - a system installed onto the layout BOOTs (systemd-boot into the
#   layout's own ESP) with every mount from `_hardware.nix` resolving:
#   device by partlabel or mapper name, fsType, subvol (via FSROOT),
#   fmask/dmask;
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

  # host -> scratch-disk size in MiB (see header: all fit the harness
  # 4G default now; kept explicit so a future layout that needs more
  # has the knob one line away).
  hosts = {
    nixos = 4096;
    framework = 4096;
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
        # the disk — partlabel devices directly, plus the framework's
        # /dev/mapper/cryptroot mounts (the dm NAME is the stable disk
        # fact the host tracks; readlink -f would collapse it to the
        # host-internal /dev/dm-N). NFS automounts are not disk facts.
        expectedMounts = lib.filterAttrs
          (_: m: lib.hasPrefix "/dev/disk/by-partlabel/" m.device
            || lib.hasPrefix "/dev/mapper/" m.device)
          (lib.mapAttrs
            (_: m: { inherit (m) device fsType options; })
            hostConfig.fileSystems);
        expectedSwap = map (s: s.device) hostConfig.swapDevices;
        # LUKS hosts: partition PARTLABEL per host, same fleet-wide
        # mapper name. The boot-phase unlock credential (see header):
        # a keyfile slot standing in for the metal TPM slot — scoped
        # to these hosts, since declaring cryptroot for harmonia would
        # fabricate a crypttab entry for a LUKS device that never
        # exists in that test.
        luksHosts = {
          framework = "framework-root";
          nixos = "nixos-root";
        };
        luksPart = luksHosts.${host} or null;
        unlockConfig = lib.optionalAttrs (luksPart != null) {
          boot.initrd.luks.devices."cryptroot".keyFile = "/tmp/secret.key";
        };
      in
      diskoLib.testLib.makeDiskoTest {
        inherit pkgs;
        name = "${host}-layout";
        disko-config = import ./computers/${host}/_disko.nix;
        extraInstallerConfig.virtualisation.emptyDiskImages =
          lib.mkForce [ scratchMiB ];
        extraSystemConfig = unlockConfig;
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
              if e['device'].startswith('/dev/mapper/'):
                  # dm devices: the mapper NAME is the identity the host
                  # config pins; readlink -f would resolve it to the
                  # host-internal /dev/dm-N and never match.
                  real = e['device']
              else:
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

          # The LUKS contract (any host whose mounts live on a mapper):
          # the PARTLABEL partition must BE the LUKS container, and the
          # booted system must be holding it open under the mapper name
          # the mounts resolve through. (The label splices in as a bare
          # Nix string, NOT toJSON — a JSON string carries double
          # quotes, and """ + "label" + """ is invalid Python; the
          # False branch keeps the block parseable-but-dead for
          # non-LUKS hosts.)
          if ${if luksPart != null then "True" else "False"}:
              part = machine.succeed(
                  "readlink -f /dev/disk/by-partlabel/${toString luksPart}").strip()
              machine.succeed(f"cryptsetup isLuks {shlex.quote(part)}")
              machine.succeed("cryptsetup status cryptroot")
        '';
      }))
    hosts;
}
