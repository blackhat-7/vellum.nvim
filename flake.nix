{
  description = "vellum.nvim: markdown preview for Neovim, packaged for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # no x86_64-darwin: nixpkgs no longer evaluates it
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      vellum = pkgs: import ./nix/package.nix {
        inherit (pkgs) lib stdenvNoCC vimUtils nodejs importNpmLock;
        src = self;
      };
    in
    {
      packages = forAllSystems (pkgs: {
        default = (vellum pkgs).plugin;
        inherit ((vellum pkgs)) plugin;
      });

      # for nixvim: `imports = [ inputs.vellum.nixvimModules.default ]`
      nixvimModules.default =
        { pkgs, ... }:
        {
          extraPlugins = [ (vellum pkgs).plugin ];
          extraPackages = [ pkgs.nodejs ];
          keymaps = [
            {
              mode = "n";
              key = "<leader>mp";
              action = "<cmd>Vellum<cr>";
              options = {
                silent = true;
                desc = "Markdown preview";
              };
            }
          ];
        };
    };
}
