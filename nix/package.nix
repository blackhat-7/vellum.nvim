{
  lib,
  stdenvNoCC,
  vimUtils,
  nodejs,
  importNpmLock,
  cacert,
  unzip,
  src,
  chromeHash ? null,
}:
let
  # The diagram renderer is a node program under render/. Upstream installs it
  # with lazy.nvim's build step (`npm ci` + `puppeteer browsers install`), which
  # cannot run inside a store path, so both are done here instead: the npm
  # dependencies come from the lockfile, and the browser is a fixed-output
  # derivation the editor is pointed at through PUPPETEER_CACHE_DIR.
  renderDeps = importNpmLock.buildNodeModules {
    npmRoot = "${src}/render";
    inherit nodejs;
  };

  chrome =
    if chromeHash == null then
      null
    else
      stdenvNoCC.mkDerivation {
        pname = "chrome-headless-shell";
        version = "puppeteer-managed";
        nativeBuildInputs = [
          nodejs
          cacert
          unzip
        ];
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = chromeHash;
        buildCommand = ''
          export HOME=$TMPDIR
          export PUPPETEER_CACHE_DIR=$out
          mkdir -p $out
          cd ${renderDeps}
          ./node_modules/.bin/puppeteer browsers install chrome-headless-shell
        '';
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
  inherit plugin chrome;
}
