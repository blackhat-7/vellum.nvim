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
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);

      # The browser is puppeteer's to manage: it downloads the headless shell it
      # expects into ~/.cache/puppeteer the first time a diagram is rendered.
      # That keeps this flake platform-agnostic. Set an entry here to pin it
      # instead, which makes the build hermetic and offline-capable — the archive
      # is the one puppeteer would fetch, and `nix store prefetch-file` on that
      # URL gives the hash. Re-do it whenever render/package-lock.json bumps
      # puppeteer, since the expected version changes with it.
      #
      # aarch64-darwin = {
      #   version = "153.0.8010.36";
      #   archive = "mac-arm64/chrome-headless-shell-mac-arm64";
      #   cacheKey = "mac_arm-153.0.8010.36";
      #   hash = "sha256-OxMzeP5EpfnISd+QSXY1d/vtKW7k0C0f+zG5/Kv3mFA=";
      # };
      chrome = { };

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
