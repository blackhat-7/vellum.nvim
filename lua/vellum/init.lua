-- Live side preview for markdown: one preview window that follows the
-- markdown buffer you are editing and scrolls with its cursor.
local render = require('vellum.render')
local theme = require('vellum.theme')
local image = require('vellum.image')
local mermaid = require('vellum.mermaid')

local api = vim.api
local M = {}

M.config = { max_width = 100 }

local ns = api.nvim_create_namespace('vellum')
local group = api.nvim_create_augroup('vellum', { clear = true })
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
  return S.win and api.nvim_win_is_valid(S.win) and S.src and api.nvim_buf_is_valid(S.src)
end

-- Scroll the preview so the block under the cursor sits at the cursor's screen row.
local function sync()
  local win = api.nvim_get_current_win()
  if not valid() or api.nvim_win_get_buf(win) ~= S.src then return end
  local row, target = api.nvim_win_get_cursor(win)[1] - 1, 0
  for _, a in ipairs(S.anchors) do
    if a[1] > row then break end
    target = row < a[1] + a[2] and a[3] + math.floor((row - a[1]) / a[2] * a[4]) or a[3] + a[4]
  end
  local screen = vim.fn.winline() - 1
  api.nvim_win_call(S.win, function()
    vim.fn.winrestview({ topline = math.max(1, target + 1 - screen), lnum = target + 1, col = 0 })
  end)
end

local function draw()
  if not valid() then return end
  local lines
  lines, S.rows, S.margin, S.anchors = render.render(S.src, api.nvim_win_get_width(S.win), M.config.max_width)
  vim.bo[S.buf].modifiable = true
  api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false
  sync()
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
mermaid.on_update = update
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
  wo.fillchars, wo.winfixbuf = 'eob: ', true
  vim.keymap.set('n', 'q', M.close, { buffer = S.buf, desc = 'Close preview' })
  theme.apply()

  local au = function(ev, fn, opts) api.nvim_create_autocmd(ev, vim.tbl_extend('force', { group = group, callback = fn }, opts or {})) end
  au({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, function(ev) if ev.buf == S.src then update() end end)
  au({ 'CursorMoved', 'CursorMovedI', 'WinScrolled' }, sync)
  au('WinResized', update)
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
  au('BufWipeout', function(ev) if ev.buf == S.src then vim.schedule(M.close) end end)
  draw()
end

function M.close()
  api.nvim_clear_autocmds({ group = group })
  if S.win and api.nvim_win_is_valid(S.win) then pcall(api.nvim_win_close, S.win, true) end
  S = {}
end

function M.toggle()
  if valid() then M.close() else M.open() end
end

return M
