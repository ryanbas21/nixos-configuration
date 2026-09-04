# Declarative partitioning for the harmonia cache server (disko).
# Exposed as flake.diskoConfigurations.harmonia (modules/disko.nix),
# consumed by the disko CLI — deliberately NOT part of the host's
# NixOS eval; this layout and _hardware.nix are independent facts
# that meet at the partition labels.
#
# The host is a QEMU/KVM guest (qemu-guest profile in _hardware.nix).
# Verified on the box 2026-09-04 (lsblk): the virtual disk enumerates
# as /dev/sda — QEMU presents it as IDE/SCSI (ata_piix, virtio_scsi;
# sr0 is the emulated CD-ROM), not virtio-blk. If the VM is ever
# recreated with a virtio-blk disk it will enumerate as /dev/vda —
# fix the two device fields below and nothing else. Partition layout
# verified at the same time: p1 = ESP (vfat, 1023M, live PARTLABEL
# "ESP"), p2 = root (ext4, 63G, live PARTLABEL "primary").
#
# Mirrors the adopted layout (nixos-generate-config 2026-09-04, root
# UUID 1450f582-…): ESP + ext4 root, no swap partition — runtime swap
# is zramSwap in the host module, and a disko run reproduces that.
#
# Fresh-metal flow: reproduces the VM's disk from scratch —
#   nix run github:nix-community/disko -- -m destroy,format,mount \
#     -f github:ryanbas21/nixos-configuration#harmonia
# NEVER point disko at the live VM's disk: destroy,format wipes it.
{ ... }: {
  disko.devices = {
    disk.sda = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            label = "harmonia-ESP";
            size = "1023M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "fmask=0022" "dmask=0022" ];
            };
          };
          root = {
            label = "harmonia-root";
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
