# Declarative partitioning for the desktop (disko). Exposed as the
# flake-level diskoConfigurations.nixos (modules/disko.nix) and consumed
# by the disko CLI — deliberately NOT part of the host's NixOS eval, so
# the layout and the host's mount table (_hardware.nix) are independent
# facts that meet at the partition labels.
#
# Fresh-metal flow (docs/bootstrap.md): boot the ISO, then
#   nix run github:nix-community/disko -- -m destroy,format,mount \
#     -f github:ryanbas21/nixos-configuration#nixos
# which partitions /dev/nvme0n1 exactly as declared below and mounts
# / and /boot under /mnt for nixos-install.
#
# The explicit labels are the contract: _hardware.nix mounts by
# /dev/disk/by-partlabel/nixos-{ESP,root}, and the live
# (hand-partitioned) disk got the same labels set once in place
# (sgdisk --change-name — see docs/bootstrap.md, "Adopting the existing
# disk"), so a disko-formatted disk and the running disk satisfy the
# identical mount config.
#
# Mirrors the original hand layout: 2G ESP, btrfs root on the rest, no
# swap. The current disk's p1/p2 are dead leftovers from a previous
# install; a disko run wipes the whole disk and takes them with it.
{ ... }: {
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
              type = "filesystem";
              format = "btrfs";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
