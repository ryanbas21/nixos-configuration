# The harmonia host's hardware facts — real nixos-generate-config
# output from the box (2026-09-04) replacing the adoption placeholder.
# The box is a QEMU/KVM guest: virtio disks, qemu-guest profile.
# nixpkgs.hostPlatform is owned by computers/harmonia.nix (explicit
# beats the generated mkDefault, so that line was dropped).
#
# Mounts follow the repo's labels contract (as computers/nixos/
# _hardware.nix does): /dev/disk/by-partlabel/harmonia-{ESP,root},
# matching the labels _disko.nix declares. The live (hand-installed)
# disk carries parted's default labels instead (p1 "ESP", p2
# "primary" — verified by lsblk 2026-09-04) and nothing on the box
# mounts by them (the live configs mount by UUID), so set the
# contract labels ONCE on the box BEFORE the first switch. Renaming
# GPT partition labels is metadata-only (data untouched):
#   sgdisk --change-name=1:harmonia-ESP --change-name=2:harmonia-root /dev/sda
# (numbering verified: p1 = ESP, p2 = root). A switch before the
# relabel cannot mount / — recover from the VM console by running
# the sgdisk line there. The generated UUIDs (root
# 1450f582-502a-48a1-bf70-6e3fc6240653, ESP D570-D6AB) are recorded
# here as the console-recovery fallback.
{ modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules =
    [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Loader lines mirror the box's hand configuration.nix (systemd-boot
  # on UEFI); _disko.nix declares the matching ESP.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/harmonia-root";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/harmonia-ESP";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # No swap partition on the box (the generated config had none);
  # runtime swap is zramSwap in the host module.
  swapDevices = [ ];
}
