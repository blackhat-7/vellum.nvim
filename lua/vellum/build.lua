-- Installing the node renderer (diagrams, display math, non-PNG images).
-- Root build.lua runs the dependency step on install; :Vellum build runs the
-- steps here, in a terminal, so npm and the browser download are visible.
local M = {}

-- npm ci must not fetch a browser (.puppeteerrc.cjs skips both downloads):
-- only :Vellum build installs chrome-headless-shell, and only when diagrams
-- are on, so a text-only setup never downloads Chromium.
M.deps = { 'npm', 'ci' }
M.browser = { 'npx', 'puppeteer', 'browsers', 'install', 'chrome-headless-shell' }

M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

-- `browser`: true or false to force the download, nil to follow the diagrams option.
function M.run(browser)
  local dir = M.root .. '/render'
  -- a package manager that builds the renderer (Nix) leaves it read-only,
  -- where npm ci can only fail
  if not vim.uv.fs_access(dir, 'W') then
    vim.notify('vellum: ' .. dir .. ' is read-only: your package manager installed the renderer, so rebuild it there', vim.log.levels.ERROR)
    return
  end
  if browser == nil then browser = require('vellum.browser').diagrams end
  local commands = { M.deps }
  if browser then table.insert(commands, M.browser) end
  local steps = vim.tbl_map(function(c) return table.concat(c, ' ') end, commands)
  vim.cmd('botright new')
  -- an argv, not :terminal {cmd}, which expands % and # in the path and runs
  -- the user's 'shell' (fish, nushell) where `&&` may not exist
  vim.fn.jobstart({ 'sh', '-c', table.concat(steps, ' && ') }, { term = true, cwd = dir })
  if not browser then
    vim.notify('vellum: diagrams are off, so no browser is installed; display math and images still need one', vim.log.levels.INFO)
  end
end

return M
