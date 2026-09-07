# Declarative partitioning for the framework laptop (disko). Exposed
# as the flake-level diskoConfigurations.framework (modules/disko.nix)
# and consumed by the disko CLI — deliberately NOT part of the host's
# NixOS eval, so the layout and the host's mount table
# (_hardware.nix) are independent facts that meet at the partition
# labels.
#
# Layout (LUKS rework of the installer-mirroring one):
#   p1  1.0G  vfat  ESP  (fmask=0077/dmask=0077, /boot)
#   p2  rest  LUKS2 "cryptroot" — btrfs inside (every btrfs mount
#        carries compress=zstd:3 + noatime — btrfsMountOptions below,
#        framework/_hardware.nix for the why): the filesystem
#        TOP-LEVEL (subvolid 5) at /, with subvolumes `home` and `nix`
#        nested (subvol=/home, subvol=/nix)
# NO swap partition anymore. The 67G one was a flash-drive-installer
# artifact adopted in 2026-09-06's mirror, never a deliberate choice:
# the fleet's memory story is zramSwap + earlyoom (system/hardware.nix,
# system/oom.nix) — and suspend is pinned to s2idle (_power.nix), so
# hibernation, disk swap's only unique purpose, is off the table. A
# plaintext swap next to an encrypted root would also quietly undo the
# LUKS story: swapped-out pages are decrypted memory.
#
# WHY LUKS (theft model, not evil-maid): a stolen POWERED-OFF laptop
# must not give up /home, /etc/nixos, or the host ssh keys — which
# today also hand over every agenix secret, since they all decrypt
# from those keys at boot. The unlock policy lives in _hardware.nix:
# a TPM2-sealed keyslot unlocks unattended (zero extra prompts — same
# boot UX as before: plymouth straight into SDDM), with the typed
# passphrase and an enrolled recovery key kept as fallbacks for the
# one case that breaks TPM sealing, a firmware update shifting PCR7.
# The boot-chain half of the threat model (Secure Boot) now lives in
# _secure-boot.nix (Lanzaboote) — this file stays the data-at-rest
# half, and the passphrase fallback below is also what carries the
# one boot where Secure Boot's PCR7 change outruns the re-seal.
#
# Fresh-metal flow (docs/bootstrap.md): boot the ISO, then
#   umask 077
#   read -rsp 'LUKS passphrase: ' pw; printf '%s' "$pw" > /tmp/secret.key
#   unset pw
#   nix run github:nix-community/disko -- -m destroy,format,mount \
#     -f github:ryanbas21/nixos-configuration#framework
#   shred -u /tmp/secret.key
# passwordFile is disko's non-interactive unlock material for
# luksFormat/luksOpen ONLY — it is NOT part of `settings`, so it never
# flows into the booted system's crypttab (settings entries DO get
# merged into boot.initrd.luks.devices by disko's _config; see the
# stanza below). printf, NOT echo: a trailing newline would become
# part of the passphrase and break the typed-at-console fallback.
# The same path is why the layout is CI-testable: the disko test
# harness seeds /tmp/secret.key ("secretsecret") before its format
# phase (disko lib/tests.nix) and into the booted initrd for the boot
# phase — the file the metal runbook creates and the file the test
# harness creates are the same fact.
#
# Post-install enrollment (on the laptop, once — TPM + recovery):
#   read -rsp 'passphrase: ' pw; printf '%s' "$pw" > /tmp/secret.key
#   sudo systemd-cryptenroll --recovery-key \
#     --unlock-key-file /tmp/secret.key /dev/disk/by-partlabel/framework-root
#   #   ^ print the recovery key INTO 1Password (and the NAS) — it is
#   #   the only credential that survives a dead TPM + forgotten
#   #   passphrase.
#   sudo systemd-cryptenroll --tpm2-device=auto \
#     --unlock-key-file /tmp/secret.key /dev/disk/by-partlabel/framework-root
#   shred -u /tmp/secret.key
# Never --wipe-slot=tpm2 the only fallbacks: keep the passphrase slot
# (slot 0, from luksFormat) AND the recovery slot alongside the TPM
# one — a BIOS/firmware update that changes Secure Boot state shifts
# PCR7, the TPM refuses to unseal, and the typed passphrase is then
# the only thing between the disk and a reinstall.
#
# MIGRATION NOTE: the live laptop disk (installed from the
# flash-drive installer 2026-09-05, labels renamed 2026-09-06) is
# UNENCRYPTED and predates this layout. It converts IN PLACE — no
# wipe, no borg restore — via `cryptsetup reencrypt --encrypt`
# (shrink btrfs, encrypt, regrow, chroot rebuild, enroll TPM): the
# step-by-step lives in docs/bootstrap.md, "Encrypting the live
# framework disk in place". Afterwards the disk satisfies this
# layout's contract exactly (same labels, LUKS2, same subvolumes) —
# modulo the dead 67G swap partition, whose reclaim runbook is in
# the same doc section. The disko wipe remains the fallback if the
# reencrypt path ever goes sideways and borg has to earn its keep.
#
# Note the btrfs spelling is the modern disko `type = "btrfs"`
# (required for subvolumes), while the ESP keeps the repo's
# `type = "filesystem"` spelling.
{ ... }:
let
  # The fleet btrfs mount options — the same list stated per-mount
  # in framework/_hardware.nix and nixos/_hardware.nix (btrfs
  # options are per-mount; subvolume mounts inherit nothing from /).
  # Here they cover the INSTALL-time mounts AND the fileSystems
  # entries disko's _config generates for hosts that eval this
  # layout — the disko test's booted system being the one that
  # matters, since this host's own eval deliberately does not import
  # it (see the header).
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
            size = "100%";
            content = {
              type = "luks";
              # The mapper name IS the contract: _hardware.nix mounts
              # /, /home and /nix from /dev/mapper/cryptroot.
              name = "cryptroot";
              passwordFile = "/tmp/secret.key";
              # Pinned though both are cryptsetup defaults, so the KDF
              # posture is self-documenting like the sshd auth posture
              # in system/base.nix.
              extraFormatArgs = [
                "--type" "luks2"
                "--pbkdf" "argon2id"
              ];
              settings = {
                # Keeps weekly fstrim (system/hardware.nix) punching
                # through the mapping; mirrored on the NixOS side in
                # _hardware.nix (disko's settings merge covers only the
                # disko-generated configs, which this host's eval does
                # not import).
                allowDiscards = true;
              };
              content = {
                type = "btrfs";
                # Content-level mountpoint = the btrfs top-level (subvolid
                # 5) mounted at /, with NO subvol option — exactly how the
                # pre-LUKS layout arranged it and how _hardware.nix
                # mounts it (via the mapper, same options as here).
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
