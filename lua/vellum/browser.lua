-- Bridge to render/browser.mjs: one long-lived headless browser turns mermaid
-- diagrams and non-PNG images into PNGs, cached on disk by content hash.
local image = require('vellum.image')

local M = {}

local root = debug.getinfo(1, 'S').source:sub(2):match('(.*)/lua/vellum/') .. '/render'
local dir = vim.fn.stdpath('cache') .. '/vellum'
local job, pending, errors, sizes = nil, {}, {}, {}

M.on_update = function() end

local function start()
  if not vim.uv.fs_stat(root .. '/node_modules') then return 'renderer not built: run :Lazy build vellum.nvim' end
  vim.fn.mkdir(dir, 'p')
  local partial, stderr = '', ''
  local ok, proc = pcall(vim.system, { 'node', root .. '/browser.mjs' }, {
    stdin = true,
    stdout = function(_, data)
      partial = partial .. (data or '')
      local lines = vim.split(partial, '\n')
      partial = table.remove(lines)
      vim.schedule(function()
        for _, line in ipairs(lines) do
          local r = vim.json.decode(line)
          pending[r.out] = nil
          errors[r.out] = r.error
          M.on_update()
        end
      end)
    end,
    stderr = function(_, data) stderr = (stderr .. (data or '')):sub(-500) end,
  }, function()
    vim.schedule(function()
      job = nil
      local why = 'renderer stopped: ' .. (vim.trim(stderr):match('[^\n]*$') or '')
      for out in pairs(pending) do errors[out] = why end
      pending = {}
      M.on_update()
    end)
  end)
  if not ok then return 'cannot start node: ' .. tostring(proc) end
  job = proc
end

-- 'ready', path, { w, h } | 'error', message | 'pending'
local function request(key, payload)
  local out = dir .. '/' .. vim.fn.sha256(key):sub(1, 32) .. '.png'
  if errors[out] then return 'error', errors[out] end
  if not sizes[out] then
    local w, h = image.png_size(out)
    if w then sizes[out] = { w, h } end
  end
  if sizes[out] then return 'ready', out, sizes[out] end
  if not pending[out] then
    if not job then
      local err = start()
      if err then return 'error', err end
    end
    pending[out] = true
    payload.out = out
    job:write(vim.json.encode(payload) .. '\n')
  end
  return 'pending'
end

function M.diagram(code, theme)
  return request(theme.signature .. code, { code = code, theme = theme.mermaid })
end

-- `src` is a local path or an http(s) URL; `version` changes when it should re-render.
function M.image(src, version)
  return request(src .. '\0' .. version, { image = src })
end

return M
