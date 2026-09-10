{
  users.batman.home.base = { ... }: {
    programs.firefox = {
      enable = true;

      profiles.default = {
        isDefault = true;

        # Search
        search = {
          force = true;

          default = "ddg";
          privateDefault = "ddg";

          engines = {
            ddg = {
              name = "DuckDuckGo";
              urls = [{
                template = "https://duckduckgo.com/?q={searchTerms}";
              }];
              definedAliases = [ "@ddg" ];
            };

            nix-packages = {
              name = "Nix Packages";
              urls = [{
                template = "https://search.nixos.org/packages";
                params = [
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }];
              definedAliases = [ "@np" ];
            };

            nix-options = {
              name = "NixOS Options";
              urls = [{
                template = "https://search.nixos.org/options";
                params = [
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }];
              definedAliases = [ "@no" ];
            };

            nix-wiki = {
              name = "NixOS Wiki";
              urls = [{
                template = "https://wiki.nixos.org/w/index.php";
                params = [
                  {
                    name = "search";
                    value = "{searchTerms}";
                  }
                ];
              }];
              definedAliases = [ "@nw" ];
            };
          };

          order = [
            "ddg"
            "nix-packages"
            "nix-options"
            "nix-wiki"
          ];
        };

        # General Firefox preferences
        settings = {
          "browser.startup.homepage" = "https://duckduckgo.com/";

          "browser.newtabpage.enabled" = true;

          # Don't ask every time where downloads go
          "browser.download.useDownloadDir" = true;

          # A little more privacy
          "privacy.trackingprotection.enabled" = true;

          # Smooth scrolling
          "general.smoothScroll" = true;
        };

        # Make Firefox's UI a little cleaner
        userChrome = ''
          /* Hide the tab bar when there's only one tab */
          #tabbrowser-tabs tab:only-of-type {
            display: none !important;
          }

          /* Make the toolbar slightly more compact */
          :root {
            --toolbar-field-border-radius: 12px !important;
          }

          #urlbar {
            border-radius: 12px !important;
          }
        '';
      };
    };
  };

}
