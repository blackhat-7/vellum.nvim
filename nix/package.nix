{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  vimUtils,
  nodejs,
  importNpmLock,
  src,
  chrome ? null,
}:
let
  # The renderer is a node program under render/. Upstream installs it with
  # lazy.nvim's build step, which cannot run inside a store path, so the
  # dependencies are built from the lockfile and linked in instead.
  renderDeps = importNpmLock.buildNodeModules {
    npmRoot = "${src}/render";
    inherit nodejs;
  };

  # Puppeteer looks for a browser it installed itself, under
  # $PUPPETEER_CACHE_DIR/chrome-headless-shell/<platform>-<version>/. The same
  # archive, unpacked into the same place, saves it the download.
  chromeHeadlessShell =
    if chrome == null then
      null
    else
      stdenvNoCC.mkDerivation {
        pname = "chrome-headless-shell";
        inherit (chrome) version;

        src = fetchurl {
          url = "https://storage.googleapis.com/chrome-for-testing-public/${chrome.version}/${chrome.archive}.zip";
          inherit (chrome) hash;
        };

        nativeBuildInputs = [ unzip ];
        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          mkdir -p $out/chrome-headless-shell/${chrome.cacheKey}
          unzip -q $src -d $out/chrome-headless-shell/${chrome.cacheKey}
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
  inherit plugin chromeHeadlessShell;
}
