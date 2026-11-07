-- :checkhealth vellum
local state = require('vellum.state')
local M = {}
local h = vim.health

function M.check()
  h.start('vellum')
  if vim.fn.has('nvim-0.12') == 1 then
    h.ok('Neovim ' .. tostring(vim.version()))
  else
    h.error('Neovim 0.12 or newer is needed')
  end
  state.backend.health(h)
end

return M
