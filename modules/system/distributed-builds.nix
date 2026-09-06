{ ... }:
{
  # Offload builds to the harmonia cache server. Note the ssh connection
  # authenticates as root with the shared ~/.ssh/harmonia key — that key
  # is GATED on the server (harmonia.nix root authorized_keys: from=
  # LAN-scope + a forced command passing through only the nix store
  # protocol), so this grants build capacity, never a root shell on the
  # signing box. The server's host key is pinned system-wide (base.nix
  # knownHosts), hence StrictHostKeyChecking=yes below — no accept-new
  # TOFU on a first connect.
  nixos.modules.base = { ... }: {
    nix.distributedBuilds = true;
    nix.settings.builders-use-substitutes = true;
    nix.buildMachines = [
      {
        hostName = "192.168.1.82";
        sshUser = "root";
        sshKey = "/home/batman/.ssh/harmonia";
        system = "x86_64-linux";
        supportedFeatures = [ "nixos-test" "big-parallel" "kvm" ];
      }
    ];
    systemd.services.nix-daemon.environment.NIX_SSHOPTS =
      "-o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o BatchMode=yes";

    programs.ssh.extraConfig = ''
      Host 192.168.1.82
        User root
        IdentityFile /home/batman/.ssh/id_borg
        IdentitiesOnly yes
    '';
  };
}
