-- Installing the node renderer (diagrams, display math, non-PNG images).
-- Root build.lua runs these steps on install; :Vellum build runs them here, in
-- a terminal, so npm and the Chrome download are visible while they run.
local M = {}

M.commands = {
  { 'npm', 'ci' },
  { 'npx', 'puppeteer', 'browsers', 'install', 'chrome-headless-shell' },
}

M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

function M.run()
  local dir = M.root .. '/render'
  -- a package manager that builds the renderer (Nix) leaves it read-only,
  -- where npm ci can only fail
  if not vim.uv.fs_access(dir, 'W') then
    vim.notify('vellum: ' .. dir .. ' is read-only: your package manager installed the renderer, so rebuild it there', vim.log.levels.ERROR)
    return
  end
  local steps = vim.tbl_map(function(c) return table.concat(c, ' ') end, M.commands)
  vim.cmd('botright new')
  -- an argv, not :terminal {cmd}, which expands % and # in the path and runs
  -- the user's 'shell' (fish, nushell) where `&&` may not exist
  vim.fn.jobstart({ 'sh', '-c', table.concat(steps, ' && ') }, { term = true, cwd = dir })
end

return M
