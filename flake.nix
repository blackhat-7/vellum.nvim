{
  description = "vellum.nvim: markdown preview for Neovim, packaged for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);

      # puppeteer's installer downloads and unpacks the browser itself, so it can
      # only run inside a fixed-output derivation. Each platform gets a different
      # shell, hence a hash per system. When puppeteer in render/package-lock.json
      # is bumped, the expected browser version changes too: set the hash below to
      # lib.fakeHash, build, and paste the value nix reports as "got:".
      chromeHashes = {
        aarch64-darwin = "sha256-n/g5+68/lT6k0xhnWEz2qT70Cp1yAuvrO22gYrmHtTs=";
      };

      mk =
        pkgs: system:
        let
          chromeHash = chromeHashes.${system} or null;
          p = import ./nix/package.nix {
            inherit (pkgs) lib stdenvNoCC vimUtils nodejs importNpmLock cacert unzip;
            src = self;
            inherit chromeHash;
          };
        in
        p;
    in
    {
      packages = forAllSystems (
        pkgs: system:
        let
          p = mk pkgs system;
        in
        {
          default = p.plugin;
          inherit (p) plugin;
        }
        // nixpkgs.lib.optionalAttrs (p.chrome != null) { chrome-headless-shell = p.chrome; }
      );

      # for nixvim: adds the plugin, node, and points puppeteer at the packaged
      # browser. Use with `imports = [ inputs.vellum.nixvimModules.default ]`.
      nixvimModules.default =
        {
          pkgs,
          lib,
          ...
        }:
        let
          p = mk pkgs pkgs.stdenv.hostPlatform.system;
        in
        {
          extraPlugins = [ p.plugin ];
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
        }
        // lib.optionalAttrs (p.chrome != null) {
          extraConfigLua = ''vim.env.PUPPETEER_CACHE_DIR = "${p.chrome}"'';
        };
    };
}
