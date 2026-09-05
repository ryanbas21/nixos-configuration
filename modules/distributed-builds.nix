{ ... }:
{
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
      "-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes";

    programs.ssh.extraConfig = ''
      Host 192.168.1.82
        User root
        IdentityFile /home/batman/.ssh/id_borg
        IdentitiesOnly yes
    '';
  };
}
