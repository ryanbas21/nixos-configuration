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
# No fileSystems/swapDevices overrides are needed (unlike the harmonia
# test's): the test framework's `useDefaultFilesystems` supplies its own
# root disk + 9p store share and drops the physical mounts — the
# desktop's by-partlabel entries, the framework's by-uuid entries and
# swap partition, and both hosts' noauto NFS automounts — automatically.
# Likewise neutralized, with reasons inline:
# - node.pkgsReadOnly = false: testers pins a shared read-only pkgs per
#   node by default, and nixos.modules.base legitimately sets
#   `nixpkgs.config.allowUnfreePredicate` (the slim harmonia host needs
#   neither).
# - the three identity-shaped home activation hooks: importGpgKey,
#   provisionCachix and hypnotixProviders each decrypt .age files inline
#   with ~/.ssh/id_borg — the one thing the reproducibility contract
#   deliberately keeps OUT of the repo (its private half lives in
#   1Password and is restored onto real installs before the first boot;
#   see docs/bootstrap.md). A test VM has no 1Password, so those three
#   hooks become no-ops: everything else — link generation, the full
#   package tree, dconf settings, the agenix registrations — activates
#   exactly as on a real first boot that HAS the keys. The agenix user
#   services that would actually decrypt only start with a login session
#   (Linger=no), which a boot test never starts.
{ config, lib, inputs, ... }:
let
  # Desktop-style hosts: full nixos.modules.base (Plasma + home-manager)
  # plus the batman user slot.
  hosts = [ "nixos" "framework" ];

  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
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
        nodes.machine = { config, lib, ... }: {
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
          home-manager.users.batman = { config, lib, ... }: {
            home.activation = {
              # See the header: 1Password-bound hooks, neutralized.
              importGpgKey = lib.mkForce (config.lib.dag.entryAnywhere "");
              provisionCachix = lib.mkForce (config.lib.dag.entryAnywhere "");
              hypnotixProviders = lib.mkForce (config.lib.dag.entryAnywhere "");
            };
          };
        };
        testScript = ''
          machine.start()
          machine.wait_for_unit("multi-user.target")
          # The boot-path home activation (the service users.nix tunes the
          # timeout of): proves the whole home — nvf, the hyprland files,
          # the agents bundle, ssh config, ... — activates cleanly on a
          # fresh boot, the exact step that fails when a real install
          # forgets to restore the identity keys first.
          machine.wait_for_unit("home-manager-batman.service")
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
          # virtio; services.smartd comes from modules/hardware.nix).
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
