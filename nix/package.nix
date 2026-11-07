{
  lib,
  stdenvNoCC,
  vimUtils,
  nodejs,
  importNpmLock,
  src,
}:
let
  # The renderer is a node program under render/. Upstream installs it with
  # lazy.nvim's build step, which cannot run inside a store path, so the
  # dependencies are built from the lockfile and linked in instead. The browser
  # it drives is puppeteer's own business — it fetches what it needs on first
  # use, which keeps this package platform-agnostic.
  renderDeps = importNpmLock.buildNodeModules {
    npmRoot = "${src}/render";
    inherit nodejs;
  };

  plugin = vimUtils.buildVimPlugin {
    name = "vellum.nvim";
    inherit src;
    # build.lua sits at the repo root for lazy.nvim; nixpkgs' require check walks
    # every .lua in the source and fails trying `require('build')`, so name the
    # module that matters instead
    nvimRequireCheck = [ "vellum" ];
    postInstall = ''
      mkdir -p $out/render
      ln -s ${renderDeps}/node_modules $out/render/node_modules
    '';
  };
in
{
  inherit plugin;
}
