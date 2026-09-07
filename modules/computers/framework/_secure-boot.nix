# Secure Boot for the framework, via Lanzaboote (github:nix-community/
# lanzaboote, release-tagged — see flake.nix). This closes the
# boot-chain half of _disko.nix's threat model: LUKS covers data at
# rest (a stolen powered-off laptop gives up nothing), Secure Boot
# covers the boot chain (code swapped onto the ESP or /boot — a
# different kernel, a doctored initrd — cannot boot; the firmware
# refuses everything not signed by our keys).
#
# HOW IT WORKS: Lanzaboote does not replace systemd-boot the loader —
# it replaces the loader INSTALLER. The menu stays systemd-boot with
# the same UX (timeout 0 from system/boot.nix; the 10-generation cap
# still holds — boot.lanzaboote.configurationLimit defaults to the
# systemd-boot option, so system/maintenance.nix needs no change). At
# switch time lzbt signs everything it writes to the ESP —
# systemd-boot itself, the per-generation lanzaboote stubs, the
# kernels — with the sbctl key set in /var/lib/sbctl (pkiBundle
# below); initrds are covered by a signed hash embedded in each stub.
# The keys live in /var/lib/sbctl on purpose: per-machine, root-only,
# mutable state — the private halves (PK/KEK/db .key files) must
# never sit world-readable in the store.
#
# RUNBOOK (metal, once; the firmware keystrokes are Framework-
# specific, the rest follows the lanzaboote docs):
#   1. Create the keys FIRST — lzbt signs at switch time, so a switch
#      without keys fails the install hook:
#        sudo sbctl create-keys
#   2. Deploy this module:
#        sudo nixos-rebuild switch --flake /etc/nixos#framework
#      Secure Boot is still off; the machine boots the newly signed
#      entries exactly as before, signatures merely unverified.
#   3. Sanity-check the ESP:
#        sudo sbctl verify
#   4. Reboot into the firmware (F2) → Administer Secure Boot → under
#      PK Options, KEK Options and DB Options, delete every entry
#      (this puts the firmware in Setup Mode). NEVER "Erase all
#      Secure Boot Settings" — Framework firmware bug that drops dbx
#      (community.frame.work/t/cant-enable-secure-boot-setup-mode/
#      57683).
#   5. Boot NixOS, enroll our keys plus the vendor sets:
#        sudo sbctl enroll-keys --microsoft --firmware-builtin
#      --firmware-builtin keeps the certs the firmware shipped with
#      (Framework BIOS updates need them); --microsoft covers option
#      ROMs (GPU, docks), which are signed by the Microsoft UEFI CA.
#   6. Reboot into the firmware → Administer Secure Boot → Enforce
#      Secure Boot → F10. (Framework firmware usually leaves SB off
#      after enrollment — the docs call this step out explicitly.)
#   7. First boot under Secure Boot asks for the LUKS passphrase:
#      PCR7 (Secure Boot policy state) shifts, so the TPM-sealed slot
#      from _hardware.nix refuses — the designed fallback (_disko.nix
#      kept the passphrase and recovery slots for exactly this).
#      Type it, then re-seal the TPM slot against the new PCR7:
#        read -rsp 'passphrase: ' pw; printf '%s' "$pw" > /tmp/secret.key
#        sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto \
#          --unlock-key-file /tmp/secret.key /dev/disk/by-partlabel/framework-root
#        shred -u /tmp/secret.key
#      The default PCR set is 7 — same policy as _disko.nix's
#      enrollment — and --wipe-slot replaces the stale pre-SB slot.
#      Kernel/generation churn never touches PCR7, so rebuilds keep
#      unlocking unattended; only SB-policy changes (re-enrolling
#      keys, a firmware "restore factory secure boot") repeat step 7.
#      EMPIRICAL (2026-09-07): the step turned out unnecessary — this
#      firmware (Insyde, AMD fTPM) does NOT extend the SB-policy
#      change into the SHA256 PCR7 bank: the whole transition (PK
#      swapped, keys enrolled, SB enforced) booted promptless, so the
#      pre-SB seal still matches. Corollary: the TPM seal here is NOT
#      bound to Secure Boot state; the passphrase/recovery fallbacks
#      remain the only guard for whatever DOES shift PCR7 someday
#      (and re-seal then, exactly as above). Binding LUKS to boot
#      state properly is systemd-pcrlock's job (lanzaboote's
#      measuredBoot + autoCryptenroll) — deliberately not taken today.
#   8. Verify: bootctl status shows "Secure Boot: enabled", sbctl
#      verify still passes, and Pareto Security's secure-boot check
#      flips green with them.
#
# KEY BACKUP: /var/lib/sbctl is the only home of the private keys and
# no borg set covers it. Losing it is recoverable (steps 1+5+7 again)
# but tedious — worth parking in 1Password next to the LUKS recovery
# key, same advice as _disko.nix's recovery-key enrollment.
#
# Honest caveat (also in the lanzaboote docs): Secure Boot without a
# firmware supervisor password is tamper-evident, not tamper-proof —
# an attacker holding the machine can enter the BIOS and turn SB off.
# Set the BIOS password during the same firmware visit as steps 4/6.
#
# The VM tests do NOT exercise this module: the signing keys are
# metal-only state, so vm-tests.nix mkForces lanzaboote off and boots
# the stock systemd-boot path (the same neutralization pattern it
# applies to LUKS).
{ pkgs, ... }:

{
  # Hand the loader seat to Lanzaboote. Plain false beats the base
  # module's mkDefault true (system/base.nix) — leaving it true would
  # run BOTH loader installers and let systemd-boot's unsigned
  # BOOTX64.EFI clobber lzbt's signed one.
  boot.loader.systemd-boot.enable = false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  # For the runbook above (create-keys/verify/status, re-enrollment).
  environment.systemPackages = [ pkgs.sbctl ];
}
