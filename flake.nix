{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ryan-nvim = {
      url = "github:ryanbas21/dotfiles";
      flake = false;
    };

    nvf = {
      url = "github:NotAShelf/nvf/v26.07";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fzf-git-sh = {
      url = "github:junegunn/fzf-git.sh";
      flake = false;
    };

  };

  outputs = { self, nixpkgs, home-manager, ryan-nvim, nvf, fzf-git-sh, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ./configuration.nix

        home-manager.nixosModules.home-manager

        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          home-manager.extraSpecialArgs = {
            inherit ryan-nvim nvf fzf-git-sh;
          };

          home-manager.users.batman = {
            imports = [
              ./home.nix
            ];
          };
        }
      ];
    };
  };
}

