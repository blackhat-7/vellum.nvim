{
  lib,
  stdenvNoCC,
  fetchzip,
  vimUtils,
  nodejs,
  importNpmLock,
  chromium,
  src,
}:
let
  # The renderer is a node program under render/. Upstream installs it with
  # lazy.nvim's build step, which cannot run inside a store path, so the
  # dependencies are built from the lockfile and linked in instead.
  renderDeps = importNpmLock.buildNodeModules {
    npmRoot = "${src}/render";
    inherit nodejs;
  };

  # Puppeteer never downloads a browser at launch, and its postinstall download
  # cannot run in the sandbox, so the browser comes from here. nixpkgs' chromium
  # is Linux-only; Chrome for Testing has a macOS headless shell but no
  # aarch64-linux build, hence one source per OS. The macOS pin matches the
  # chrome-headless-shell version of puppeteer in render/package-lock.json.
  browser =
    if stdenvNoCC.hostPlatform.isLinux then
      lib.getExe chromium
    else if stdenvNoCC.hostPlatform.system == "aarch64-darwin" then
      let
        version = "153.0.8010.36";
        shell = fetchzip {
          url = "https://storage.googleapis.com/chrome-for-testing-public/${version}/mac-arm64/chrome-headless-shell-mac-arm64.zip";
          hash = "sha256-wsX1WSPoAAXHcWe7KZMwrfcmdColigcpKipIsAPM0FY=";
        };
      in
      "${shell}/chrome-headless-shell"
    else
      throw "vellum.nvim: no headless browser packaged for ${stdenvNoCC.hostPlatform.system}";
in
vimUtils.buildVimPlugin {
  name = "vellum.nvim";
  inherit src;
  # browser.lua starts the renderer in render/, where puppeteer reads this config
  postInstall = ''
    ln -s ${renderDeps}/node_modules $out/render/node_modules
    echo 'module.exports.executablePath = ${builtins.toJSON browser};' >> $out/render/.puppeteerrc.cjs
  '';
}
