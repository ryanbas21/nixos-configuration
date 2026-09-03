{ ... }: {
  users.batman.home.base = { ... }:
    { pkgs, ... }:
    let
      hypnotix-x11 = pkgs.symlinkJoin {
        name = "hypnotix-x11";
        paths = [ pkgs.hypnotix ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/hypnotix \
            --set GDK_BACKEND x11 \
            --prefix PATH : ${pkgs.glib}/bin
        '';
      };
    in
    {
      home.packages = [ hypnotix-x11 ];

      dconf.settings."org/x/hypnotix" = {
        mpv-options = "hwdec=auto-safe vo=x11";
      };
    };
}
