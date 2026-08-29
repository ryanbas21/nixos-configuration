{ pkgs, ryan-nvim, ... }:

{
programs.neovim = {
  enable = true;
  initLua = ''
    vim.lsp.config('nixd', {
      cmd = { 'nixd' },
      filetypes = { 'nix' },
      root_markers = { 'flake.nix', '.git' },
      settings = {
        nixd = {
          nixpkgs = {
            expr = "import <nixpkgs> { }";
          },
          formatting = {
            command = { "nixfmt" };
          },
          options = {
            nixos = {
              expr = "(builtins.getFlake \"/etc/nixos\").nixosConfigurations.YOUR_HOSTNAME.options";
            };
            home_manager = {
              expr = "(builtins.getFlake \"/etc/nixos\").homeConfigurations.YOUR_USER.options";
            };
          };
        };
      };
    })
    vim.lsp.enable('nixd')
  '';
};

  xdg.configFile."nvim".source =
    "${ryan-nvim}/nvim/.config/nvim";
}

