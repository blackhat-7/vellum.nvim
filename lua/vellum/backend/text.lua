-- The zero-Chromium backend: diagrams as code, display math as text, images
-- as alt text, and HTML-only exports through render/export.mjs.
local code = require('vellum.code')
local install = require('vellum.install')

local root = debug.getinfo(1, 'S').source:sub(2):match('(.*)/lua/vellum/') .. '/render'

local M = {}

function M.diagram(source, width, row, lang) return code.panel(source, lang, width) end
function M.math() return nil end
function M.image() return nil end
function M.inline() return nil end
function M.reset() end
function M.dir() end
function M.waiting() return 0 end
function M.drop_stale() end
function M.configure() end
function M.warning() return nil end

M.commands = { install.deps }
M.note = 'vellum: chromium = false, so no browser is installed'
M.extension = 'html' -- the default :Vellum export output

local exports = {}
function M.export(req, done)
  if exports[req.out] then return done('already exporting to ' .. req.out) end
  if req.out:lower():match('%.pdf$') then
    return done('PDF export needs Chromium; with chromium = false, export to .html')
  end
  if vim.fn.executable('node') == 0 then return done('node not found: export needs Node.js 20.6 or newer') end
  if not vim.uv.fs_stat(root .. '/node_modules') then return done('renderer not built: run :Vellum build') end
  exports[req.out] = done
  local function finish(err)
    exports[req.out] = nil
    done(err)
  end
  local partial, stderr, answered = '', '', false
  local ok, proc = pcall(vim.system, { 'node', root .. '/export.mjs' }, {
    cwd = root,
    stdin = true,
    stdout = function(_, data)
      partial = partial .. (data or '')
      local lines = vim.split(partial, '\n')
      partial = table.remove(lines)
      for _, line in ipairs(lines) do
        local parsed, r = pcall(vim.json.decode, line)
        if parsed and r.out and not answered then
          answered = true
          vim.schedule(function() finish(r.error) end)
        end
      end
    end,
    stderr = function(_, data) stderr = (stderr .. (data or '')):sub(-500) end,
  }, function()
    vim.schedule(function()
      if not answered then
        answered = true
        finish('export stopped: ' .. (vim.trim(stderr):match('[^\n]*$') or ''))
      end
    end)
  end)
  if not ok then
    exports[req.out] = nil
    return done('cannot start node: ' .. tostring(proc))
  end
  proc:write(vim.json.encode(req) .. '\n')
end

function M.health(h)
  h.info('Chromium is off (chromium = false): mermaid and D2 show as code, display math as text, images as alt text')
  h.info('export writes HTML only; PDF and browser-backed pictures need chromium = true')
  local ok, r = pcall(function() return vim.system({ 'node', '--version' }, { text = true }):wait() end)
  local v = ok and r.code == 0 and vim.version.parse(r.stdout)
  if not v then
    h.warn('node not found. HTML export needs Node.js 20.6 or newer')
  elseif vim.version.lt(v, { 20, 6, 0 }) then
    h.warn('node ' .. tostring(v) .. ' is too old. HTML export needs 20.6 or newer')
  else
    h.ok('node ' .. tostring(v))
    if vim.uv.fs_stat(root .. '/node_modules') then
      h.ok('renderer built (HTML export)')
    else
      h.warn('renderer not built: HTML export needs it', { 'Run :Vellum build' })
    end
  end
  h.info('images are off (chromium = false): they show as alt text')
end

return M
