-- Bridge to render/browser.mjs: one long-lived headless browser turns mermaid
-- diagrams, display math and non-PNG images into PNGs, cached on disk by content hash.
local image = require('vellum.image')

local M = {}

local root = debug.getinfo(1, 'S').source:sub(2):match('(.*)/lua/vellum/') .. '/render'
local dir = vim.fn.stdpath('cache') .. '/vellum'
local job, pending, errors, sizes, wanted = nil, {}, {}, {}, {}

M.on_update = function() end

-- Keep the cache under 100 MB, least recently used out first. Runs once per
-- session, before any file is shown; request() bumps the mtime of files it uses.
local function prune()
  local files, total = {}, 0
  for name in vim.fs.dir(dir) do
    local st = vim.uv.fs_stat(dir .. '/' .. name)
    if st and st.type == 'file' then
      files[#files + 1] = { dir .. '/' .. name, st.mtime.sec, st.size }
      total = total + st.size
    end
  end
  table.sort(files, function(a, b) return a[2] < b[2] end)
  for _, f in ipairs(files) do
    if total <= 100 * 1024 * 1024 then break end
    os.remove(f[1])
    total = total - f[3]
  end
end
prune()

-- Start the renderer, if it is not running. Loading Chrome and mermaid takes
-- ~0.7 s, so the preview starts it on open rather than on the first diagram.
-- Returns an error message, or nil.
function M.start()
  if job then return end
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
    if w then
      sizes[out] = { w, h }
      vim.uv.fs_utime(out, os.time(), os.time())
    end
  end
  if sizes[out] then return 'ready', out, sizes[out] end
  if not pending[out] then
    local err = M.start()
    if err then return 'error', err end
    pending[out] = true
    payload.out = out
    job:write(vim.json.encode(payload) .. '\n')
  end
  wanted[out] = true
  return 'pending'
end

-- Cancel queued renders the last draw did not ask for. Typing inside a
-- diagram queues one render per keystroke, and only the newest matters.
function M.drop_stale()
  for out in pairs(pending) do
    if not wanted[out] then
      pending[out] = nil
      job:write(vim.json.encode({ cancel = out }) .. '\n')
    end
  end
  wanted = {}
end

function M.diagram(code, theme)
  return request(theme.signature .. code, { code = code, theme = theme.mermaid })
end

-- Display math in text color `color`.
function M.math(tex, color)
  return request('math\0' .. color .. '\0' .. tex, { math = tex, color = color })
end

-- `src` is a local path or an http(s) URL; `version` changes when it should re-render.
function M.image(src, version)
  return request(src .. '\0' .. version, { image = src })
end

return M
