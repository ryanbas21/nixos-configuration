{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # nixpkgs unstable (26.11) dropped x86_64-darwin; the 26.05-darwin
    # stable branch is nixpkgs' supported substitute for Intel Macs and
    # feeds only the ryan-intel-mac standalone home-manager export.
    nixpkgs-intel-mac.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

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

    flake-parts.url = "github:hercules-ci/flake-parts";

    import-tree = {
      url = "github:vic/import-tree";
      flake = false;
    };

  };

  outputs = inputs: import ./outputs.nix inputs;
}
