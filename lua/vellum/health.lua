-- :checkhealth vellum
local M = {}
local h = vim.health

-- A real render: it proves the build, Chrome and the renderer at once. The
-- text is new each time, so a cached picture cannot stand in for it.
local function renderer()
  local browser, theme = require('vellum.browser'), require('vellum.theme')
  theme.apply()
  local code = 'flowchart LR\n  A[checkhealth ' .. vim.uv.hrtime() .. ']'
  local state, err
  vim.wait(20000, function()
    state, err = browser.diagram(code, theme)
    return state ~= 'pending'
  end, 100)
  if state == 'ready' then
    h.ok('renderer works (mermaid diagram rendered)')
  else
    h.error('renderer failed: ' .. (err or 'no answer in 20 s'), { 'Rebuild it: :Vellum build' })
  end
end

local function images()
  local image = require('vellum.image')
  if not image.supported then
    h.warn("this terminal can't show images, so diagrams show as code and images as their alt text",
      { 'Use kitty or Ghostty. In tmux, vellum asks tmux which terminal is attached.' })
  elseif image.problem() then
    h.warn(image.problem())
  else
    h.ok('images show in this terminal')
  end
end

function M.check()
  h.start('vellum')
  if vim.fn.has('nvim-0.12') == 1 then
    h.ok('Neovim ' .. tostring(vim.version()))
  else
    h.error('Neovim 0.12 or newer is needed')
  end

  -- import.meta.resolve, which the renderer uses, is stable from Node 20.6
  local ok, r = pcall(function() return vim.system({ 'node', '--version' }, { text = true }):wait() end)
  local v = ok and r.code == 0 and vim.version.parse(r.stdout)
  if not v then
    h.error('node not found. Diagrams, display math and non-PNG images need Node.js 20.6 or newer')
  elseif vim.version.lt(v, { 20, 6, 0 }) then
    h.error('node ' .. tostring(v) .. ' is too old. Diagrams, display math and non-PNG images need 20.6 or newer')
  else
    h.ok('node ' .. tostring(v))
    renderer()
  end
  images()
end

return M
