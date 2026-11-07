-- Installing the node renderer. Root build.lua runs the dependency step on
-- install; :Vellum build runs the active backend's steps in a terminal, so npm
-- and the browser download are visible while they run.
local install = require('vellum.install')
local state = require('vellum.state')

local M = {}

M.deps, M.browser = install.deps, install.browser -- the root hook and tests read these
M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

function M.run()
  local dir = M.root .. '/render'
  -- a package manager that builds the renderer (Nix) leaves it read-only,
  -- where npm ci can only fail
  if not vim.uv.fs_access(dir, 'W') then
    vim.notify('vellum: ' .. dir .. ' is read-only: your package manager installed the renderer, so rebuild it there', vim.log.levels.ERROR)
    return
  end
  local steps = vim.tbl_map(function(c) return table.concat(c, ' ') end, state.backend.commands)
  vim.cmd('botright new')
  -- an argv, not :terminal {cmd}, which expands % and # in the path and runs
  -- the user's 'shell' (fish, nushell) where `&&` may not exist
  vim.fn.jobstart({ 'sh', '-c', table.concat(steps, ' && ') }, { term = true, cwd = dir })
  if state.backend.note then vim.notify(state.backend.note, vim.log.levels.INFO) end
end

return M
