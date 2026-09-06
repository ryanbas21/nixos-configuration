# USBGuard for the framework — TEMPLATE, DELIBERATELY NOT IMPORTED.
#
# Nothing imports this file (that is the point of the underscore: the
# repo's convention for manual-import data). Enabling USBGuard blind
# would lock out every external USB device AND several INTERNAL ones —
# the fingerprint reader, camera, and audio sit on internal USB hubs,
# and a blocked fingerprint reader bricks the PAM login path
# (framework/_pam.nix). The policy must be generated ON the laptop,
# against its actual devices; a wrong policy is a lockout, not a
# config error CI can catch.
#
# RUNBOOK (do this on the laptop, once):
#   1. Plug in everything you ever want allowed (dock, mouse, keys...).
#   2. Generate the policy:
#        sudo nix shell nixpkgs#usbguard -c usbguard generate-policy
#      (or, once usbguard is enabled: `sudo usbguard generate-policy`)
#   3. Paste the output into `rules` below, replacing the placeholder.
#      Sanity-check that it includes the INTERNAL devices (fingerprint
#      reader is a Goodix / framework hub device; verify with
#      `lsusb` against the generated lines) BEFORE proceeding.
#   4. Import this file from framework.nix's imports list.
#   5. `sudo nixos-rebuild switch --flake .#framework`, then verify
#      fingerprint login and one external device still work — with
#      the laptop's password path still available as the fallback.
#
# Threat model: evil-maid / malicious-charger USB attacks while
# traveling. The desktop (never leaves the LAN closet of the house)
# does not need this.
{ ... }:
{
  services.usbguard = {
    enable = true;
    # Implicit policy applies to devices NOT matched by any rule:
    # block. Rules below must therefore cover everything legitimate.
    rules = ''
      # TODO(on the laptop): paste `sudo usbguard generate-policy` here
      # — see the runbook in this file's header. Placeholder rule keeps
      # the file importable-but-empty until then:
      allow-id 1d6b:0002
      allow-id 1d6b:0003
    '';
  };
}
