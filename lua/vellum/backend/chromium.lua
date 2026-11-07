-- The Chromium backend: diagrams, display math and images as pictures, and
-- exports through the long-lived headless browser.
local browser = require('vellum.browser')
local code = require('vellum.code')
local image = require('vellum.image')
local install = require('vellum.install')
local media = require('vellum.media')
local state = require('vellum.state')
local theme = require('vellum.theme')

local M = {}

-- The renderer answers in the background; init.lua owns the redraw callback.
browser.on_update = function() state.on_update() end

local last_diagram, last_math = {}, {}

function M.reset()
  last_diagram, last_math = {}, {}
end

function M.diagram(source, width, row, lang)
  if not image.supported then return code.panel(source, lang, width) end
  local problem = image.problem()
  if problem then return code.panel(source, lang, width, nil, problem) end
  local result, a, b = browser.diagram(source, theme, lang, media.dir)
  if result == 'ready' then
    last_diagram[row] = media.picture(a, b[1], b[2], width, b[3])
    return last_diagram[row]
  elseif result == 'error' then
    return code.panel(source, lang, width, nil, a)
  end
  return last_diagram[row] or code.panel(source, lang, width, 'rendering…')
end

function M.math(tex, width, key)
  if not image.supported or image.problem() then return nil end
  local result, a, b = browser.math(tex, theme.math)
  if result == 'ready' then
    local lines = media.picture(a, b[1], b[2], width, b[3])
    if key then last_math[key] = lines end
    return lines
  elseif result == 'error' then
    return nil, a
  end
  return key and last_math[key]
end

M.image, M.inline = media.image, media.inline

function M.dir(path) media.dir = path end
function M.waiting() return browser.waiting end
M.drop_stale = browser.drop_stale
function M.configure(opts) browser.max_pixels = opts.max_pixels end
function M.export(req, done) browser.export(req, done) end

function M.warning()
  return not image.supported and "this terminal can't show images (kitty and Ghostty can), so diagrams show as code"
    or image.problem()
end

M.commands = { install.deps, install.browser }
M.note = nil
M.extension = 'pdf' -- the default :Vellum export output

-- Health: node, a real render, D2, images.
local function images(h)
  if not image.supported then
    h.warn("this terminal can't show images, so diagrams show as code and images as their alt text",
      { 'Use kitty or Ghostty. In tmux, vellum asks tmux which terminal is attached.' })
  elseif image.problem() then
    h.warn(image.problem())
  else
    h.ok('images show in this terminal')
  end
end

function M.health(h)
  local ok, r = pcall(function() return vim.system({ 'node', '--version' }, { text = true }):wait() end)
  local v = ok and r.code == 0 and vim.version.parse(r.stdout)
  local need = 'Diagrams, display math and non-PNG images'
  if not v then
    h.error('node not found. ' .. need .. ' need Node.js 20.6 or newer')
  elseif vim.version.lt(v, { 20, 6, 0 }) then
    h.error('node ' .. tostring(v) .. ' is too old. ' .. need .. ' need 20.6 or newer')
  else
    h.ok('node ' .. tostring(v))
    theme.apply()
    local function render(source, lang)
      local result, err
      vim.wait(20000, function()
        result, err = browser.diagram(source, theme, lang)
        return result ~= 'pending'
      end, 100)
      return result == 'ready', err or (result == 'pending' and 'no answer in 20 s')
    end
    local rendered, err = render('flowchart LR\n  A[checkhealth ' .. vim.uv.hrtime() .. ']', 'mermaid')
    if not rendered then
      h.error('renderer failed: ' .. err, { 'Rebuild it: :Vellum build' })
    else
      h.ok('renderer works (mermaid diagram rendered)')
      rendered, err = render('checkhealth -> ' .. vim.uv.hrtime(), 'd2')
      if rendered then
        local d2 = browser.d2_command()
        h.ok('D2 diagrams render, with ' .. (d2 and d2.bin .. ' ' .. d2.version or 'the bundled D2'))
        if not d2 then h.info('Install d2 (https://d2lang.com) to render with its newer version and your layout plugins') end
      else
        h.error('D2 failed: ' .. err, { 'Rebuild the renderer: :Vellum build' })
      end
    end
  end
  images(h)
end

return M
