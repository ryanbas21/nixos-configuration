# Declarative partitioning for the desktop (disko). Exposed as the
# flake-level diskoConfigurations.nixos (modules/disko.nix) and consumed
# by the disko CLI — deliberately NOT part of the host's NixOS eval, so
# the layout and the host's mount table (_hardware.nix) are independent
# facts that meet at the partition labels.
#
# LUKS rework (2026-09-06, framework first — see
# computers/framework/_disko.nix for the full threat model, the
# passwordFile/test-harness interplay and the enrollment runbooks).
# Same shape here: ESP stays plaintext, the btrfs root moves inside a
# LUKS2 container, mapper name `cryptroot` is the contract
# _hardware.nix mounts through. The desktop's TPM was confirmed on the
# box (2026-09-06, /dev/tpmrm0 — Intel PTT), so boot stays UNATTENDED
# (the WoL suspend/wake flow in batman/ssh.nix depends on it).
# The extra reason THIS box earns encryption despite never leaving
# the house: it holds id_borg (the key that decrypts the borg repo —
# plaintext-endpoint-plus-plaintext-repo-key would quietly undo the
# framework's encryption) and the gated harmonia push identity.
#
# MIGRATION: the live disk is unencrypted and converts in place
# (cryptsetup reencrypt — same runbook as the framework's, with the
# desktop's partition-number deltas, in docs/bootstrap.md "Encrypting
# the live framework disk in place"). One difference that matters:
# the desktop reboots headless (WoL, nobody at a console), so BOTH
# keyslot enrolls (recovery + TPM) happen from the live session
# BEFORE the first reboot — see the runbook's desktop deltas.
#
# NOTE the live disk does NOT match this layout's partition COUNT: it
# carries dead p1/p2 leftovers from a previous install BEFORE the ESP
# (p3) and root (p4). Those satisfy nothing and are wiped by any
# disko run; they cannot be merged into root (wrong side of the
# partition table).
{ ... }:
let
  # Fleet btrfs mount options — same list as framework/_disko.nix
  # (and the per-mount lists in both hosts' _hardware.nix); the
  # disko test compares these against the host's tracked table.
  btrfsMountOptions = [ "compress=zstd:3" "noatime" ];
in
{
  disko.devices = {
    disk.nvme0n1 = {
      device = "/dev/nvme0n1";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            label = "nixos-ESP";
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "fmask=0022" "dmask=0022" ];
            };
          };
          root = {
            label = "nixos-root";
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              passwordFile = "/tmp/secret.key";
              extraFormatArgs = [
                "--type" "luks2"
                "--pbkdf" "argon2id"
              ];
              settings = {
                allowDiscards = true;
              };
              content = {
                type = "btrfs";
                # the filesystem TOP-LEVEL (subvolid 5) at /, with
                # `nix` and `home` nested subvolumes — identical to
                # the pre-LUKS layout, now behind the mapper (and
                # with the fleet btrfs options, like the framework).
                mountpoint = "/";
                mountOptions = btrfsMountOptions;
                subvolumes = {
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = btrfsMountOptions;
                  };
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = btrfsMountOptions;
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
