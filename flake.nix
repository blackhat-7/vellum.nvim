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

      # The headless shell puppeteer downloads for the version pinned in
      # render/package-lock.json. `nix store prefetch-file` the same URL to fill
      # in a new hash when puppeteer is bumped; systems not listed here get no
      # browser and puppeteer downloads one on first use.
      chrome = {
        aarch64-darwin = {
          version = "153.0.8010.36";
          archive = "mac-arm64/chrome-headless-shell-mac-arm64";
          cacheKey = "mac_arm-153.0.8010.36";
          hash = "sha256-OxMzeP5EpfnISd+QSXY1d/vtKW7k0C0f+zG5/Kv3mFA=";
        };
      };

      mk =
        pkgs: system:
        import ./nix/package.nix {
          inherit (pkgs) lib stdenvNoCC fetchurl unzip vimUtils nodejs importNpmLock;
          src = self;
          chrome = chrome.${system} or null;
        };
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
        // nixpkgs.lib.optionalAttrs (p.chromeHeadlessShell != null) {
          inherit (p) chromeHeadlessShell;
        }
      );

      # for nixvim: `imports = [ inputs.vellum.nixvimModules.default ]`
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
        // lib.optionalAttrs (p.chromeHeadlessShell != null) {
          extraConfigLua = ''vim.env.PUPPETEER_CACHE_DIR = "${p.chromeHeadlessShell}"'';
        };
    };
}
