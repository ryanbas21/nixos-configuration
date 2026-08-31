{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    psysonic.url = "github:Psysonic/psysonic";

    rigup = {
      url = "github:YPares/rigup.nix";
      flake = true;
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ryan-nvim = {
      url = "github:ryanbas21/dotfiles";
      flake = false;
    };

    fzf-git-sh = {
      url = "github:junegunn/fzf-git.sh";
      flake = false;
    };

  };

  outputs = { self, nixpkgs, home-manager, ryan-nvim, fzf-git-sh, rigup, psysonic, ... }: 
      let 
        system = "x86_64-linux";
      in 
  {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {

      modules = [
        {
          nixpkgs.hostPlatform = system;
        }

        ./configuration.nix

        home-manager.nixosModules.home-manager

        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";

          home-manager.extraSpecialArgs = {
            inherit ryan-nvim fzf-git-sh rigup;
          };

          home-manager.users.batman = {
            imports = [
              ./home.nix
            ];
            home.packages = [
              psysonic.packages.${system}.psysonic
            ];
          };
        }
      ];
    };
  };
}

