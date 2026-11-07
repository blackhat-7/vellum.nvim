{
  description = "vellum.nvim: markdown preview for Neovim, packaged for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      # no x86_64-darwin: nixpkgs no longer evaluates it
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # only what the plugin reads at runtime; docs/ alone is several MB
      src = lib.sourceByRegex self [
        "LICENSE"
        "lua(/.*)?"
        "plugin(/.*)?"
        "render(/.*)?"
      ];
      vellum = pkgs: pkgs.callPackage ./nix/package.nix { inherit src; };
    in
    {
      packages = forAllSystems (pkgs: rec {
        plugin = vellum pkgs;
        default = plugin;
      });

      # for nixvim: `imports = [ inputs.vellum.nixvimModules.default ]`
      nixvimModules.default =
        { pkgs, ... }:
        {
          extraPlugins = [ (vellum pkgs) ];
          extraPackages = [ pkgs.nodejs ];
        };
    };
}
