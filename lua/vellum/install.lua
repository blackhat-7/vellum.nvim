-- Installing the node renderer. npm ci must not fetch a browser
-- (.puppeteerrc.cjs skips both downloads); the browser is a separate step that
-- only the Chromium backend uses.
local M = {}

M.deps = { 'npm', 'ci' }
M.browser = { 'npx', 'puppeteer', 'browsers', 'install', 'chrome-headless-shell' }

return M
