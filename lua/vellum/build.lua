-- Installing the node renderer (mermaid, display math, non-PNG images).
-- Root build.lua runs these steps on install; :Vellum build runs them here, in
-- a terminal, so npm and the Chrome download are visible while they run.
local M = {}

M.commands = {
  { 'npm', 'ci' },
  { 'npx', 'puppeteer', 'browsers', 'install', 'chrome-headless-shell' },
}

M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

function M.run()
  local cmd = 'cd ' .. vim.fn.shellescape(M.root .. '/render')
  for _, c in ipairs(M.commands) do cmd = cmd .. ' && ' .. table.concat(c, ' ') end
  vim.cmd('terminal ' .. cmd)
end

return M
