-- Live side preview for markdown: one preview window that follows the
-- markdown buffer you are editing and scrolls with its cursor.
local render = require('vellum.render')
local theme = require('vellum.theme')
local image = require('vellum.image')
local browser = require('vellum.browser')
local zoom = require('vellum.zoom')

local api = vim.api
local M = {}

M.config = { max_width = 100 }

local ns = api.nvim_create_namespace('vellum')
local group = api.nvim_create_augroup('vellum', { clear = true })
local warned = false -- told the user why images cannot show
local S = {} -- win, buf: the preview · src: the markdown buffer · rows, margin: highlights · anchors: scroll map

-- Highlights are applied only to lines being drawn, so a redraw costs the
-- same for a 50-line and a 5,000-line document.
api.nvim_set_decoration_provider(ns, {
  on_win = function(_, _, buf) return buf == S.buf end,
  on_line = function(_, _, buf, row)
    for _, m in ipairs(S.rows[row + 1] or {}) do
      api.nvim_buf_set_extmark(buf, ns, row, m[1] + S.margin, {
        end_col = m[2] + S.margin, hl_group = m[3], priority = m[4], ephemeral = true,
      })
    end
  end,
})

local function valid()
  return S.win and api.nvim_win_is_valid(S.win) and S.src and api.nvim_buf_is_loaded(S.src)
end

-- Each side records the view it set on the other (S.top: preview topline,
-- S.view: source topline and cursor), so the scroll it causes there is not
-- synced straight back.
local function view(win)
  local v = api.nvim_win_call(win, vim.fn.winsaveview)
  return v.topline .. ':' .. v.lnum
end

-- Scroll the preview so the block under the cursor sits at the cursor's screen row.
local function sync(force)
  local win = api.nvim_get_current_win()
  if not valid() or api.nvim_win_get_buf(win) ~= S.src then return end
  if force ~= true and view(win) == S.view then return end
  S.view = nil
  local row, target = api.nvim_win_get_cursor(win)[1] - 1, 0
  for _, a in ipairs(S.anchors) do
    if a[1] > row then break end
    target = row < a[1] + a[2] and a[3] + math.floor((row - a[1]) / a[2] * a[4]) or a[3] + a[4]
  end
  local screen = vim.fn.winline() - 1
  api.nvim_win_call(S.win, function()
    vim.fn.winrestview({ topline = math.max(1, target + 1 - screen), lnum = target + 1, col = 0 })
    S.top = vim.fn.winsaveview().topline
  end)
end

-- Scroll the source so the block at the preview's top sits at the source's top.
local function follow()
  local win = vim.fn.bufwinid(S.src)
  if not valid() or win == -1 then return end
  local top = api.nvim_win_call(S.win, vim.fn.winsaveview).topline - 1
  local target = 0
  for _, a in ipairs(S.anchors) do
    if a[3] > top then break end
    target = top < a[3] + a[4] and a[1] + math.floor((top - a[3]) / a[4] * a[2]) or a[1] + a[2]
  end
  api.nvim_win_call(win, function()
    -- <C-e>/<C-y> drag the cursor along; setting topline alone would not
    local d = target + 1 - vim.fn.winsaveview().topline
    if d ~= 0 then vim.cmd(('normal! %d%s'):format(math.abs(d), d > 0 and '\5' or '\25')) end
  end)
  S.view = view(win)
end

local function scrolled()
  local mine = vim.v.event[tostring(S.win)] and valid()
  -- Lines already fit the width, and a sideways shift hides the image cells
  -- that carry the placement diacritics, so kitty garbles every row.
  if mine and vim.v.event[tostring(S.win)].leftcol ~= 0 then
    api.nvim_win_call(S.win, function() vim.fn.winrestview({ leftcol = 0 }) end)
  end
  if mine and api.nvim_win_call(S.win, vim.fn.winsaveview).topline ~= S.top then
    follow()
  elseif vim.v.event[tostring(api.nvim_get_current_win())] then
    sync()
  end
end

local function draw()
  if not valid() then return end
  local lines
  lines, S.rows, S.margin, S.anchors = render.render(S.src, api.nvim_win_get_width(S.win), M.config.max_width)
  browser.drop_stale()
  vim.bo[S.buf].modifiable = true
  api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false
  sync(true)
end

-- Coalesce bursts of events into one draw on the next tick.
local queued = false
local function update()
  if queued then return end
  queued = true
  vim.schedule(function()
    queued = false
    draw()
  end)
end
browser.on_update = update

-- Dragging a split fires WinResized for every column. Re-rendering each time
-- (and re-placing every image in the terminal) makes the drag lag, so draw
-- once it settles.
local settle = vim.uv.new_timer()
local function resized()
  if vim.tbl_contains(vim.v.event.windows, S.win) then settle:start(80, 0, vim.schedule_wrap(draw)) end
end
M.redraw = draw

function M.setup(opts) M.config = vim.tbl_extend('force', M.config, opts or {}) end

function M.open()
  if valid() then return end
  S = { src = api.nvim_get_current_buf(), buf = api.nvim_create_buf(false, true), anchors = {}, rows = {}, margin = 0 }
  vim.bo[S.buf].bufhidden = 'wipe'
  api.nvim_buf_set_name(S.buf, 'vellum://preview')
  S.win = api.nvim_open_win(S.buf, false, { split = 'right', win = api.nvim_get_current_win() })
  local wo = vim.wo[S.win][0]
  wo.number, wo.relativenumber, wo.signcolumn, wo.foldcolumn, wo.statuscolumn = false, false, 'no', '0', ''
  wo.wrap, wo.list, wo.spell, wo.cursorline, wo.colorcolumn = false, false, false, false, ''
  -- scrolloff would move the topline sync sets, and follow() would echo it back
  wo.fillchars, wo.winfixbuf, wo.scrolloff = 'eob: ', true, 0
  vim.keymap.set('n', 'q', M.close, { buffer = S.buf, desc = 'Close preview' })
  vim.keymap.set('n', '<CR>', M.zoom, { buffer = S.buf, desc = 'Zoom the image' })
  theme.apply()
  if image.supported and not image.problem() then browser.start() end
  -- The preview falls back to text on its own; say why, once a session.
  local why = not image.supported and "this terminal can't show images (kitty and Ghostty can), so diagrams show as code"
    or image.problem()
  if why and not warned then
    warned = true
    vim.notify('vellum: ' .. why .. '\nMore: :checkhealth vellum', vim.log.levels.WARN)
  end

  local au = function(ev, fn, opts) api.nvim_create_autocmd(ev, vim.tbl_extend('force', { group = group, callback = fn }, opts or {})) end
  au({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, function(ev) if ev.buf == S.src then update() end end)
  au({ 'CursorMoved', 'CursorMovedI' }, sync)
  au('WinScrolled', scrolled)
  au('WinResized', resized)
  au('BufEnter', function(ev)
    if ev.buf ~= S.src and vim.bo[ev.buf].filetype == 'markdown' then
      S.src = ev.buf
      update()
    end
  end)
  au('ColorScheme', function()
    theme.apply()
    render.reset()
    update()
  end)
  -- a re-attached tmux session may sit in a new terminal that lost the images
  au('FocusGained', function()
    image.reset()
    render.reset()
    update()
  end)
  au('WinClosed', function() vim.schedule(M.close) end, { pattern = tostring(S.win) })
  -- A preview whose source no window shows has nothing to follow, and an
  -- unloaded source renders empty. Checked after the event, because BufEnter
  -- may have moved the preview to the markdown buffer that replaced it.
  au({ 'BufHidden', 'BufUnload' }, function(ev)
    if ev.buf ~= S.src then return end
    vim.schedule(function()
      if S.win and (not api.nvim_buf_is_loaded(S.src) or #vim.fn.win_findbuf(S.src) == 0) then M.close() end
    end)
  end)
  -- Closing the source's window must not leave the preview alone in the tab:
  -- close it first, so :q quits the way it would without a preview.
  au('QuitPre', function()
    local wins = vim.tbl_filter(function(w) return api.nvim_win_get_config(w).relative == '' end, api.nvim_tabpage_list_wins(0))
    if #wins == 2 and vim.tbl_contains(wins, S.win) and api.nvim_get_current_win() ~= S.win then M.close() end
  end)
  draw()
end

function M.close()
  api.nvim_clear_autocmds({ group = group })
  settle:stop()
  if S.win and api.nvim_win_is_valid(S.win) then pcall(api.nvim_win_close, S.win, true) end
  S = {}
end

-- Open the image on the preview's cursor line full-screen. That line follows
-- the source cursor, so this works from either window.
function M.zoom()
  if not valid() then return end
  for _, m in ipairs(S.rows[api.nvim_win_get_cursor(S.win)[1]] or {}) do
    local id = tonumber(m[3]:match('Img(%d+)'))
    if id and image.paths[id] then return zoom.open(image.paths[id]) end
  end
  vim.notify('vellum: no image on this line', vim.log.levels.INFO)
end

function M.toggle()
  if valid() then M.close() else M.open() end
end

return M
