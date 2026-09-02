{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # nixpkgs unstable (26.11) dropped x86_64-darwin; the 26.05-darwin
    # stable branch is nixpkgs' supported substitute for Intel Macs and
    # feeds only the ryan-intel-mac standalone home-manager export.
    nixpkgs-intel-mac.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Secrets (home-manager module + agenix CLI). Upstream moves rarely:
    # rev b027ee2 (2026-02-03) was still HEAD when checked 2026-09-01 —
    # verify with `nix flake metadata github:ryantm/agenix` before
    # assuming the lock entry is stale (see README, "Updating inputs").
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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

    psysonic.url = "github:Psysonic/psysonic";

    llm-agents.url = "github:numtide/llm-agents.nix";

    rigup.url = "github:YPares/rigup.nix";

    flake-parts.url = "github:hercules-ci/flake-parts";

    import-tree = {
      url = "github:vic/import-tree";
      flake = false;
    };

    vicinae.url = "github:vicinaehq/vicinae";

  };

  outputs = inputs: import ./outputs.nix inputs;
}
