{
  nixos.modules.base = {
    services.ntpd-rs = {
      enable = true;
      settings.observability.log-level = "warn";
    };
  };
}
