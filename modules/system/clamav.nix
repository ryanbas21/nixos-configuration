{
  nixos.modules.base = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.clamav ];
    # enable antivirus clamav and
    # keep the signatures' database updated
    services.clamav.daemon.enable = true;
    services.clamav.updater.enable = true;
  };
}
