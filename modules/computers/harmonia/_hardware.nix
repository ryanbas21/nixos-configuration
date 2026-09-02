# PLACEHOLDER — replace before first deploy:
#   ssh root@192.168.1.82
#   nixos-generate-config   # writes /etc/nixos/hardware-configuration.nix
# and copy the generated content here. This placeholder is a valid (if
# empty) module, so CI stays green until adoption; an empty module sets
# no fileSystems, so do NOT actually deploy against it.
{ ... }:

{
  # Placeholder root so the host evaluates (NixOS asserts a root FS
  # exists); REPLACE with the nixos-generate-config output before
  # deploying — the device below intentionally does not exist, so an
  # accidental deploy against the placeholder fails at activation.
  fileSystems."/" = {
    device = "/dev/disk/by-id/REPLACE-ME-at-adoption";
    fsType = "ext4";
  };

  # Assumes a recent default install (systemd-boot on UEFI). Verify with
  # `bootctl status` on the box before the first switch; the generated
  # hardware-configuration.nix will carry the real answer anyway.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
