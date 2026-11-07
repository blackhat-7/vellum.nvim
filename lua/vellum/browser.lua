-- Bridge to render/browser.mjs: one long-lived headless browser turns mermaid
-- and D2 diagrams, display math and non-PNG images into PNGs, cached on disk by content hash.
local image = require('vellum.image')

local M = {}

local root = debug.getinfo(1, 'S').source:sub(2):match('(.*)/lua/vellum/') .. '/render'
local dir = vim.fn.stdpath('cache') .. '/vellum'
local job, pending, errors, sizes, wanted = nil, {}, {}, {}, {} -- pending: out → request
local exports = {} -- out → function(error) to call when the export is done

M.on_update = function() end
M.waiting = 0 -- counts every answer 'pending': output showing one must not be cached
M.max_pixels = nil -- most pixels in one rendered PNG, from setup(); nil for no cap

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

local send -- below; a restarted renderer resends through it

-- Start the renderer, if it is not running. Loading Chrome and mermaid takes
-- ~0.7 s, so the preview starts it on open rather than on the first diagram.
-- Returns an error message, or nil.
function M.start()
  if job then return end
  if vim.fn.executable('node') == 0 then return 'node not found: diagrams need Node.js 20.6 or newer' end
  if not vim.uv.fs_stat(root .. '/node_modules') then return 'renderer not built: run :Vellum build' end
  vim.fn.mkdir(dir, 'p')
  local partial, stderr, answered = '', '', false
  local ok, proc = pcall(vim.system, { 'node', root .. '/browser.mjs' }, {
    -- puppeteer reads its config (.puppeteerrc.*) from the working directory:
    -- render/.puppeteerrc.cjs applies (Nix names its browser there), a user's project one does not
    cwd = root,
    stdin = true,
    stdout = function(_, data)
      partial = partial .. (data or '')
      local lines = vim.split(partial, '\n')
      partial = table.remove(lines)
      vim.schedule(function()
        for _, line in ipairs(lines) do
          local done, r = pcall(vim.json.decode, line)
          if done and r.out then
            answered = true
            local finished = exports[r.out]
            exports[r.out] = nil
            if finished then
              finished(r.error)
            else
              pending[r.out] = nil
              errors[r.out] = r.error
              M.on_update()
            end
          end
        end
      end)
    end,
    stderr = function(_, data) stderr = (stderr .. (data or '')):sub(-500) end,
  }, function()
    vim.schedule(function()
      job = nil
      for _, finished in pairs(exports) do finished('renderer stopped') end
      exports = {}
      local waiting = pending
      pending = {}
      if answered then
        -- it worked before, so Chrome or node crashed: start again and resend
        -- what was waiting. A request that kills it again fails below.
        for out, req in pairs(waiting) do send(out, req) end
      else
        -- it never worked: a broken setup, which restarting would not fix
        local why = 'renderer stopped: ' .. (vim.trim(stderr):match('[^\n]*$') or '')
        for out in pairs(waiting) do errors[out] = why end
      end
      M.on_update()
    end)
  end)
  if not ok then return 'cannot start node: ' .. tostring(proc) end
  job = proc
end

-- Queue a render, starting the renderer if needed. Returns an error message, or nil.
function send(out, req)
  local err = M.start()
  if err then return err end
  pending[out] = req
  req.out = out
  job:write(vim.json.encode(req) .. '\n')
end

-- 'ready', path, { w, h, density } | 'error', message | 'pending'
-- density is PNG pixels per CSS px.
local function request(key, payload)
  if M.max_pixels then
    -- a capped PNG is another picture than the full-scale one
    key = key .. '\0max' .. M.max_pixels
    payload.maxPixels = M.max_pixels
  end
  local out = dir .. '/' .. vim.fn.sha256(key):sub(1, 32) .. '.png'
  if errors[out] then return 'error', errors[out] end
  if not sizes[out] then
    local w, h, density = image.png_size(out)
    if w then
      -- PNGs from before the renderer wrote pHYs are all 2x
      sizes[out] = { w, h, density or 2 }
      vim.uv.fs_utime(out, os.time(), os.time())
    end
  end
  if sizes[out] then return 'ready', out, sizes[out] end
  if not pending[out] then
    local err = send(out, payload)
    if err then return 'error', err end
  end
  wanted[out] = true
  M.waiting = M.waiting + 1
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

-- Write req.markdown, whose relative links resolve in req.dir, to req.out: a
-- .pdf or .html file, drawing D2 as diagrams do. req.kinds maps callout types to colors. Calls
-- done(error) when finished; error is nil on success.
function M.export(req, done)
  if exports[req.out] then return done('already exporting to ' .. req.out) end
  local err = M.start()
  if err then return done(err) end
  exports[req.out] = done
  local d2 = M.d2_command()
  req.d2bin = d2 and d2.bin
  job:write(vim.json.encode(req) .. '\n')
end

-- Local D2 icon files are part of the picture, so their versions are part of
-- its key: an edited icon renders anew, like an edited image (media.lua).
local function icon_versions(code, dir)
  local out = {}
  for line in code:gmatch('[^\n]+') do
    for value in line:gmatch('icon%s*:%s*([^;}]+)') do
      local path = vim.trim(value):gsub('^(["\'])(.*)%1$', '%2')
      if not path:match('^%a[%w+.-]*:') then -- a URL is fetched as it is
        local stat = vim.uv.fs_stat(vim.fs.joinpath(dir, path))
        out[#out + 1] = path .. '\0' .. (stat and stat.mtime.sec .. '.' .. stat.size or '')
      end
    end
  end
  return table.concat(out, '\0')
end

-- The user's d2 command, { bin, version }, or nil; looked up once. D2 renders
-- with it when installed (newer than the bundled D2, with the user's layout
-- plugins such as TALA), else with the bundled one.
local d2_found
function M.d2_command()
  if d2_found == nil then
    local bin = vim.fn.exepath('d2')
    local r = bin ~= '' and vim.system({ bin, '--version' }, { text = true }):wait()
    d2_found = r and r.code == 0 and { bin = bin, version = vim.trim(r.stdout) } or false
  end
  return d2_found or nil
end

-- A diagram in `lang`, 'mermaid' or 'd2', in the colorscheme's colors. D2's
-- local icons resolve in `dir`, the markdown file's folder.
function M.diagram(code, theme, lang, dir)
  if lang == 'd2' then
    dir = dir or vim.fn.getcwd()
    local d2 = M.d2_command()
    -- which d2 draws it is part of the picture: installing or upgrading one renders anew
    local by = d2 and d2.bin .. ' ' .. d2.version or 'bundled'
    local key = table.concat({ 'd2', by, theme.d2_signature, dir, icon_versions(code, dir), code }, '\0')
    return request(key, { d2 = code, theme = theme.d2, dir = dir, bin = d2 and d2.bin })
  end
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
