# Fresh-boot VM smoke tests for the two desktop-style hosts (`nixos`,
# `framework`) — the CI-side answer to "does a freshly installed machine
# actually boot?". Each test boots the REAL host module (the exact module
# nixosConfigurations.<host> deploys, tracked hardware file and all) as a
# UEFI QEMU guest and asserts the state a first boot must reach:
# multi-user.target, the boot-path home-manager activation, the batman
# account, the core base-module services, and no failed units.
#
# This is the integration-testing pattern from
# https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines
# (nixpkgs `testers.runNixOSTest`); the harmonia host keeps its own
# dedicated test next to its module (computers/harmonia/vm-test.nix)
# because it asserts cache semantics, not just boot. A new desktop-style
# host joins simply by adding its name to `hosts` below.
#
# Secret decryption — the part that makes these two hosts special — runs
# FOR REAL here, against committed throwaway material: `modules/vm-tests/`
# holds a throwaway ed25519 identity (playing ~/.ssh/id_borg — the real
# one's private half lives only in 1Password and must never reach a CI
# runner) and .age files encrypted to it; the three production modules
# expose their hook inputs as `activationSecrets.*` options
# (batman/agenix.nix, cachix.nix, hypnotix.nix — defaults are the real
# 1Password-bound secrets), which the test points at the throwaway
# files. The hooks themselves are the production code, unmodified: rage
# decrypt with the identity file, GPG import + ownertrust pin, cachix
# dhall materialization + gh sync, dconf write. What stays untested is
# only the real key/secret BYTES — their handling code is exactly what
# runs on every push. (Same pattern as the harmonia test's committed
# test-signing-key.nixkey.)
#
# Regenerating the material in vm-tests/ (all throwaway; regenerate
# freely — update testGpgFingerprint below if the GPG key changes):
#   ssh-keygen -t ed25519 -N "" -C "vm-test-identity: throwaway" -f test-identity
#   ...gpg --batch --quick-gen-key "VM Test <vm-test@invalid>" ed25519 cert never
#   printf <plaintext> | rage -R test-identity.pub > test-<name>.age
# The .age files MUST be encrypted with rage to the SSH PUBLIC key
# (`rage -R test-identity.pub`) — that is the exact counterpart of the
# hooks' `rage -d -i ~/.ssh/id_borg`. Encrypting with `age` to the
# ssh-to-age-CONVERTED age1 recipient does NOT match rage's ssh
# identity handling and the hooks fail with "No matching keys found"
# (learned the hard way, 2026-09-06).
#
# No fileSystems/swapDevices overrides are needed (unlike the harmonia
# test's): the test framework's `useDefaultFilesystems` supplies its own
# root disk + 9p store share and drops the physical mounts — both
# hosts' by-partlabel entries, the framework's /dev/mapper mounts, and
# the noauto NFS automounts — automatically.
# Likewise neutralized, with reasons inline:
# - node.pkgsReadOnly = false: testers pins a shared read-only pkgs per
#   node by default, and nixos.modules.base legitimately sets
#   `nixpkgs.config.allowUnfreePredicate` (the slim harmonia host needs
#   neither).
# - the agenix user services (age.secrets) are left registered but
#   never run: they decrypt at session start (Linger=no), and a boot
#   test starts no login session.
# - snapper configs are dropped (mkForce {}): the test root from
#   useDefaultFilesystems is not btrfs, so a timeline fire that
#   happened to land inside the test window would just fail — the
#   same environmental-mismatch neutralization as the dropped mounts
#   above (on metal the root is btrfs and the timeline snapshots; see
#   system/snapper.nix).
# - system age.secrets are dropped (mkForce {}): a test VM's freshly
#   generated host key matches no age recipient, so the decrypt unit
#   would fail; the alerting scripts no-op on the missing secret file
#   by design (the runtime consumers read it, tests never run them).
# - the framework's LUKS declaration is dropped (mkForce {}): the
#   crypttab entry points at a partition that exists only on metal,
#   and a QEMU guest has no TPM either — stage-1 systemd-cryptsetup
#   would sit waiting on both. Same environmental-mismatch
#   neutralization as the dropped mounts above; the disko test
#   (disko-tests.nix) exercises the REAL unlock path on a REAL
#   LUKS-formatted disk instead.
{ config, lib, inputs, ... }:
let
  # Desktop-style hosts: full nixos.modules.base (Plasma + home-manager)
  # plus the batman user slot.
  hosts = [ "nixos" "framework" ];

  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  # The throwaway GPG key inside vm-tests/test-gpg.age (its fingerprint
  # is the ownertrust pin the test asserts).
  testGpgFingerprint = "007C335566F316CE65AD976B5BFC43D7801A9AF3";
in
{
  flake.checks.x86_64-linux = lib.genAttrs
    (map (host: "${host}:vm-test") hosts)
    (checkName:
      let
        host = lib.head (lib.splitString ":" checkName);
        hostEval = config.nixos.configurations.${host};
        # Baked into the testScript so a wrong host module silently
        # booting fails the test, not just the hostname check.
        expectedHostname = hostEval.configuration.config.networking.hostName;
      in
      pkgs.testers.runNixOSTest {
        name = "${host}-vm-test";
        node.pkgsReadOnly = false;
        nodes.machine = { ... }: {
          imports = [ hostEval.module ];
          # systemd-boot requires UEFI on real metal, so boot UEFI here
          # too. The generous memory/cores: the Plasma-era closure runs
          # under TCG emulation on CI runners (no /dev/kvm there), and
          # the home activation is link-heavy.
          virtualisation = {
            useEFIBoot = true;
            memorySize = 4096;
            cores = 2;
          };
          # See header: not btrfs in the test root.
          services.snapper.configs = lib.mkForce { };
          # See header: a test VM's host key matches no recipient, so
          # the agenix decrypt unit for the ntfy URL would fail — drop
          # the declaration entirely (harmonia's test does the same).
          age.secrets = lib.mkForce { };
          # See header: metal-only LUKS device (framework) — the VM has
          # neither the partition nor a TPM to unlock it with.
          boot.initrd.luks.devices = lib.mkForce { };
          # The throwaway identity must exist BEFORE home activation —
          # exactly like a real install, where the runbook restores
          # ~/.ssh/id_borg onto the target before first boot. It cannot
          # be a home.file entry: hypnotixProviders chains after
          # dconfSettings, which runs before writeBoundary/linkGeneration
          # — the hook would race (and lose against) the link step.
          systemd.services.vm-test-identity = {
            description = "Seed throwaway ~/.ssh/id_borg for the VM test";
            # nss-lookup: user/group resolution may not be live yet at
            # early boot (nsncd races), and install validates -o/-g
            # names against it. Owner-only flags: the dir needs no group
            # change — mode 700 + owner batman grants everything the
            # activation requires.
            before = [ "home-manager-batman.service" ];
            after = [ "nss-lookup.target" ];
            wantedBy = [ "home-manager-batman.service" ];
            serviceConfig.Type = "oneshot";
            script = ''
              # Mirror the runbook's key-restore + chown exactly: the
              # directory must be batman's too, or linkGeneration cannot
              # create ~/.ssh/config beside it (the bare-metal runbook
              # pays for this with its nixos-enter chown step).
              install -d -m 700 -o batman /home/batman/.ssh
              install -m 600 -o batman ${./vm-tests/test-identity} /home/batman/.ssh/id_borg
            '';
          };
          home-manager.users.batman = { lib, ... }: {
            # The three REAL activation hooks, fed throwaway inputs
            # (mkForce beats the feature files' real-value assignments;
            # the options are declared in home-manager.nix).
            activationSecrets.gpg.file = lib.mkForce ./vm-tests/test-gpg.age;
            activationSecrets.gpg.fingerprint = lib.mkForce testGpgFingerprint;
            activationSecrets.cachix.authToken = lib.mkForce ./vm-tests/test-cachix-auth-token.age;
            activationSecrets.cachix.signingKey = lib.mkForce ./vm-tests/test-cachix-signing-key.age;
            activationSecrets.hypnotixProviders = lib.mkForce ./vm-tests/test-hypnotix-providers.age;
          };
        };
        testScript = ''
          machine.start()
          machine.wait_for_unit("multi-user.target")
          # The boot-path home activation (the service users.nix tunes the
          # timeout of): proves the whole home — nvf, the hyprland files,
          # the agents bundle, ssh config, the secret-decrypting hooks,
          # ... — activates cleanly on a fresh boot.
          machine.wait_for_unit("home-manager-batman.service")
          # The REAL identity-shaped hooks ran with the throwaway
          # identity (throwaway plaintexts, safe to assert on):
          machine.succeed("su - batman -c 'gpg --list-secret-keys ${testGpgFingerprint} >/dev/null'")
          trust = machine.succeed("su - batman -c 'gpg --export-ownertrust'")
          assert "${testGpgFingerprint}:6:" in trust, trust
          machine.succeed("grep -q test-token-vm-tests /home/batman/.config/cachix/cachix.dhall")
          machine.succeed("grep -aq vm-test:::xtream /home/batman/.config/dconf/user")
          # Core base-module services.
          machine.succeed("systemctl is-active NetworkManager.service")
          machine.succeed("systemctl is-active sshd.service")
          # The account the config creates (users.nix): wheel +
          # networkmanager, fish as the shell (users.defaultUserShell).
          ident = machine.succeed("id batman")
          assert "wheel" in ident, ident
          assert "networkmanager" in ident, ident
          passwd = machine.succeed("getent passwd batman").strip()
          assert passwd.endswith("/bin/fish"), passwd
          # The right host module actually booted.
          assert machine.succeed("hostname").strip() == "${expectedHostname}"
          # Both Wayland sessions (Plasma + the relinked hyprland) ship
          # in the closure.
          machine.succeed("ls /run/current-system/sw/share/wayland-sessions/ | grep -q .")
          # Fresh-boot health: nothing may fail except smartd — the one
          # environmental casualty of QEMU (no SMART devices behind
          # virtio; services.smartd comes from modules/system/hardware.nix).
          failed = [
            line
            for line in machine.succeed(
              "systemctl list-units --state=failed --no-legend"
            ).splitlines()
            if line.strip() and "smartd.service" not in line
          ]
          assert not failed, "\n".join(failed)
        '';
      });
}
