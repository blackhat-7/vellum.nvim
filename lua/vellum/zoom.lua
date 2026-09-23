-- Full-screen viewer for one image. Zooming re-places the image at a bigger
-- cell box (a few bytes to the terminal); panning only changes which of its
-- cells the placeholder text names. Pixels are sent once, when it opens. The
-- viewer uses its own image id, so the preview's copy is never disturbed.
local image = require('vellum.image')

local api = vim.api
local M = {}

local ns = api.nvim_create_namespace('vellum.zoom')
local STEP = 1.25

function M.open(path)
  local pw, ph = image.png_size(path)
  if not pw then return end
  local id = image.id(path .. '#zoom')
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  local win
  local settle = vim.uv.new_timer()
  local z, fx, fy = 1, 0.5, 0.5 -- zoom over fit-to-screen; view center as a fraction of the image

  -- The view's size and the image's full cell box at the current zoom.
  local function size()
    local w, h = api.nvim_win_get_width(win), api.nvim_win_get_height(win) - 1 -- the winbar takes a row
    local cw, ch = image.cell()
    local fit = math.min(w * cw / pw, h * ch / ph) -- screen px per image px
    -- kitty addresses at most max_cells rows and columns of one image
    local zmax = math.min(image.max_cells * cw / (pw * fit), image.max_cells * ch / (ph * fit))
    z = math.min(z, zmax)
    return w, h, math.max(1, math.floor(pw * fit * z / cw)), math.max(1, math.floor(ph * fit * z / ch)), z >= zmax
  end

  local function draw()
    local w, h, cols, rows, max = size()
    local nc, nr = math.min(w, cols), math.min(h, rows)
    local c0 = math.max(0, math.min(cols - nc, math.floor(fx * cols - nc / 2 + 0.5)))
    local r0 = math.max(0, math.min(rows - nr, math.floor(fy * rows - nr / 2 + 0.5)))
    -- read the center back, so panning past an edge does not build up
    fx, fy = (c0 + nc / 2) / cols, (r0 + nr / 2) / rows

    local pad, top = string.rep(' ', math.floor((w - nc) / 2)), math.floor((h - nr) / 2)
    local lines = {}
    for i = 1, h do lines[i] = '' end
    local cells = image.grid(id, path, cols, rows, r0, c0, nr, nc)
    for i, l in ipairs(cells) do lines[top + i] = pad .. l[1][1] end
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for i, l in ipairs(cells) do
      api.nvim_buf_set_extmark(buf, ns, top + i - 1, #pad, { end_col = #pad + #l[1][1], hl_group = l[1][2] })
    end
    settle:start(100, 0, vim.schedule_wrap(function() image.resend(id) end))
    vim.wo[win].winbar = ('%%#VellumMuted# %d%%%%%s  +/-/ctrl-wheel zoom · hjkl/wheel pan · 0 fit · q close'):format(z * 100 + 0.5, max and ' (max)' or '')
  end

  local function layout()
    local config = { relative = 'editor', row = 0, col = 0, width = vim.o.columns, height = vim.o.lines - vim.o.cmdheight }
    if win then
      api.nvim_win_set_config(win, config)
    else
      win = api.nvim_open_win(buf, true, vim.tbl_extend('force', config, { style = 'minimal', zindex = 100 }))
      vim.wo[win].winhighlight, vim.wo[win].wrap = 'NormalFloat:Normal', false
    end
    draw()
  end

  local group = api.nvim_create_augroup('vellum.zoom', { clear = true })
  local function close() if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end end
  layout()
  api.nvim_create_autocmd('VimResized', { group = group, callback = layout })
  -- the placeholder text must stay put: a scrolled view shifts or cuts the image
  api.nvim_create_autocmd('WinScrolled', { group = group, pattern = tostring(win), callback = function()
    api.nvim_win_call(win, function() vim.fn.winrestview({ topline = 1, leftcol = 0 }) end)
  end })
  -- a viewer left behind another window would hold stale state
  api.nvim_create_autocmd('WinLeave', { group = group, buffer = buf, callback = vim.schedule_wrap(close) })
  api.nvim_create_autocmd('BufWipeout', { group = group, buffer = buf, callback = function()
    settle:close()
    image.drop(id)
    api.nvim_del_augroup_by_id(group)
  end })

  local function map(keys, fn)
    for _, k in ipairs(keys) do vim.keymap.set('n', k, function() fn() draw() end, { buffer = buf, nowait = true }) end
  end
  -- dx, dy: how far to move, as a fraction of the view
  local function pan(dx, dy)
    return function()
      local w, h, cols, rows = size()
      fx, fy = fx + dx * w / cols, fy + dy * h / rows
    end
  end
  -- Zoom by factor k, keeping the image point under the mouse (or the
  -- view's center) where it is.
  local function zoom(k, mouse)
    return function()
      local w, h, cols, rows = size()
      local m, dx, dy = vim.fn.getmousepos(), 0, 0
      if mouse and m.winid == win then dx, dy = m.wincol - 1 - w / 2, m.winrow - 2 - h / 2 end -- winrow 1 is the winbar
      local px, py = fx + dx / cols, fy + dy / rows
      z = math.max(1, z * k)
      _, _, cols, rows = size()
      fx, fy = px - dx / cols, py - dy / rows
    end
  end
  map({ '+', '=' }, zoom(STEP))
  map({ '-' }, zoom(1 / STEP))
  map({ '<C-ScrollWheelUp>' }, zoom(STEP, true))
  map({ '<C-ScrollWheelDown>' }, zoom(1 / STEP, true))
  map({ '0' }, function() z, fx, fy = 1, 0.5, 0.5 end)
  map({ 'h', '<Left>' }, pan(-0.25, 0))
  map({ 'l', '<Right>' }, pan(0.25, 0))
  map({ 'k', '<Up>' }, pan(0, -0.25))
  map({ 'j', '<Down>' }, pan(0, 0.25))
  map({ '<ScrollWheelLeft>' }, pan(-0.1, 0))
  map({ '<ScrollWheelRight>' }, pan(0.1, 0))
  map({ '<ScrollWheelUp>' }, pan(0, -0.1))
  map({ '<ScrollWheelDown>' }, pan(0, 0.1))
  for _, k in ipairs({ 'q', '<Esc>' }) do vim.keymap.set('n', k, close, { buffer = buf, nowait = true }) end
end

return M
