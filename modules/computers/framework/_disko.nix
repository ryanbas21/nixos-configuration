# Declarative partitioning for the framework laptop (disko). Exposed
# as the flake-level diskoConfigurations.framework (modules/disko.nix)
# and consumed by the disko CLI — deliberately NOT part of the host's
# NixOS eval, so the layout and the host's mount table
# (_hardware.nix) are independent facts that meet at the partition
# labels.
#
# Mirrors the layout the NixOS flash-drive installer made on
# 2026-09-05 (verified on the box 2026-09-06, lsblk/findmnt):
#   p1  1.0G  vfat  ESP  (fmask=0077/dmask=0077, /boot)
#   p2  863.8G btrfs root — the filesystem TOP-LEVEL (subvolid 5) is
#        mounted at /, with subvolumes `home` and `nix` nested in it
#        (subvol=/home, subvol=/nix)
#   p3  66.7G swap
# The installer's own PARTLABELs (EFI/root/swap) were renamed once, in
# place, to the fleet convention (sgdisk --change-name; metadata-only,
# see docs/bootstrap.md "Adopting the existing disk") — so the live
# installer disk and a disko-formatted disk satisfy the identical
# _hardware.nix. Note the btrfs spelling is the modern disko
# `type = "btrfs"` (required for subvolumes), while the ESP keeps the
# repo's `type = "filesystem"` spelling.
#
# Fresh-metal flow (docs/bootstrap.md): boot the ISO, then
#   nix run github:nix-community/disko -- -m destroy,format,mount \
#     -f github:ryanbas21/nixos-configuration#framework
# which partitions /dev/nvme0n1 exactly as declared below and mounts
# /, /boot, /home and /nix under /mnt for nixos-install.
{ ... }: {
  disko.devices = {
    disk.nvme0n1 = {
      device = "/dev/nvme0n1";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            label = "framework-ESP";
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "fmask=0077" "dmask=0077" ];
            };
          };
          root = {
            label = "framework-root";
            # everything between the ESP and the last 67G (the swap) —
            # size-relative, so a bigger disk grows the root, like the
            # desktop's layout. `end` counts from the disk's end.
            end = "-67G";
            content = {
              type = "btrfs";
              # Content-level mountpoint = the btrfs top-level (subvolid
              # 5) mounted at /, with NO subvol option — exactly how the
              # installer arranged it and how _hardware.nix mounts it.
              mountpoint = "/";
              subvolumes = {
                "/nix" = { mountpoint = "/nix"; };
                "/home" = { mountpoint = "/home"; };
              };
            };
          };
          swap = {
            label = "framework-swap";
            # "100%" = the remaining disk, created last (disko gives it
            # priority 9001) — here the final ~67G, after root's -67G
            # end. The live installer disk: 66.7G.
            size = "100%";
            content = {
              type = "swap";
            };
          };
        };
      };
    };
  };
}
