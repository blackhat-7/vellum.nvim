-- Live side preview for markdown: one preview window that follows the
-- markdown buffer you are editing and scrolls with its cursor.
local render = require('vellum.render')
local theme = require('vellum.theme')
local image = require('vellum.image')
local browser = require('vellum.browser')
local zoom = require('vellum.zoom')
local links = require('vellum.links')
local mdx = require('vellum.mdx')
local code = require('vellum.code')

local api = vim.api
local M = {}

M.config = { max_width = 100, tab = false, split = 'right', auto_open = false }
-- every option and its type; max_pixels and size default to nil
local OPTIONS = { max_width = 'number', max_pixels = 'number', tab = 'boolean', split = 'string', size = 'number', auto_open = 'boolean' }
local SPLITS = { right = true, left = true, above = true, below = true }

local ns = api.nvim_create_namespace('vellum')
local group = api.nvim_create_augroup('vellum', { clear = true })
local warned = false -- told the user why images cannot show
local S = {} -- win, buf: the preview · src: the markdown buffer · rows, margin: highlights · anchors: scroll map

-- Diagrams still rendering show a spinner in their label (code.lua).
local SPINNER = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local frame = 1
local spin = vim.uv.new_timer()
local wake = vim.uv.new_timer() -- draws again when a slow render's loader is due

-- The spinner text over mark m: the first glyph of a 'rendering' label, or
-- a badge over the cells of a picture being updated (4 bytes per cell).
local function spinner(m)
  if m[3] == 'VellumSpinner' then return { { SPINNER[frame], 'VellumSpinner' } } end
  if m[3] ~= 'VellumBadge' then return nil end
  local cells = (m[2] - m[1]) / 4
  local text = cells >= 12 and ' ' .. SPINNER[frame] .. ' updating ' or cells >= 3 and ' ' .. SPINNER[frame] .. ' ' or SPINNER[frame]
  return { { text, 'VellumBadge' } }
end

-- Highlights are applied only to lines being drawn, so a redraw costs the
-- same for a 50-line and a 5,000-line document.
api.nvim_set_decoration_provider(ns, {
  on_win = function(_, _, buf)
    if buf ~= S.buf then return false end
    image.next_frame()
  end,
  on_line = function(_, _, buf, row)
    for _, m in ipairs(S.rows[row + 1] or {}) do
      api.nvim_buf_set_extmark(buf, ns, row, m[1] + S.margin, {
        end_col = m[2] + S.margin, hl_group = m[3], priority = m[4], ephemeral = true,
        -- the spinner turns by redrawing the screen alone, not the document
        virt_text = spinner(m), virt_text_pos = spinner(m) and 'overlay' or nil,
      })
      -- an image is sent to the terminal when a row of it is first drawn
      local id = image.id_of(m[3])
      if id then image.show(id) end
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

-- `pos` mapped across the anchors { src_row, src_rows, out_line, out_lines }:
-- fields i, i+1 are its side, j, j+1 the other. Within a block, proportional.
local function across(pos, i, j)
  local target = 0
  for _, a in ipairs(S.anchors) do
    if a[i] > pos then break end
    target = pos < a[i] + a[i + 1] and a[j] + math.floor((pos - a[i]) / a[i + 1] * a[j + 1]) or a[j] + a[j + 1]
  end
  return target
end

-- Scroll the preview so the block under the cursor sits at the cursor's screen row.
local function sync(force)
  local win = api.nvim_get_current_win()
  if not valid() or api.nvim_win_get_buf(win) ~= S.src then return end
  if force ~= true and view(win) == S.view then return end
  S.view = nil
  local target = across(api.nvim_win_get_cursor(win)[1] - 1, 1, 3)
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
  local target = across(api.nvim_win_call(S.win, vim.fn.winsaveview).topline - 1, 3, 1)
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

-- tab mode puts the focus, and its window pins the buffer, where Tab keys the user
-- associates with moving around must move tab pages; their own bindings return on close
local TAB_KEYS = { ['<Tab>'] = 'tabnext', gt = 'tabnext', ['<S-Tab>'] = 'tabprevious' }
local function tabkeys(buf)
  for key, cmd in pairs(TAB_KEYS) do
    vim.keymap.set('n', key, '<Cmd>' .. cmd .. '<cr>', { buffer = buf, desc = cmd == 'tabnext' and 'Next tab page' or 'Previous tab page' })
  end
end

local update -- below: draw schedules it when a loader is due

local function draw()
  if not valid() then return end
  local lines, shown
  lines, S.rows, S.margin, S.anchors, shown = render.render(S.src, api.nvim_win_get_width(S.win), M.config.max_width)
  browser.drop_stale()
  image.keep(shown)
  vim.bo[S.buf].modifiable = true
  api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false
  sync(true)
  if code.wake then
    wake:start(code.wake, 0, vim.schedule_wrap(update))
    code.wake = nil
  end
  if browser.busy() and not spin:is_active() then
    spin:start(100, 100, vim.schedule_wrap(function()
      if not valid() or not browser.busy() then return spin:stop() end
      frame = frame % #SPINNER + 1
      api.nvim__redraw({ win = S.win, valid = false })
    end))
  end
end

-- Coalesce bursts of events into one draw on the next tick.
local queued = false
function update()
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
local replace = vim.uv.new_timer() -- its own: a shared one would cancel a pending resize redraw
local function resized()
  if vim.tbl_contains(vim.v.event.windows, S.win) then settle:start(80, 0, vim.schedule_wrap(draw)) end
end
M.redraw = draw

-- A mistyped or misspelled option is skipped with a warning; it would
-- otherwise do nothing without a word.
function M.setup(opts)
  local bad = {}
  for k, v in pairs(opts or {}) do
    local want = OPTIONS[k]
    if not want then
      bad[#bad + 1] = ('unknown option %q'):format(k)
    elseif type(v) ~= want then
      bad[#bad + 1] = ('%s should be a %s, not %s'):format(k, want, type(v))
    elseif k == 'split' and not SPLITS[v] then
      bad[#bad + 1] = ('split should be right, left, above or below, not %q'):format(v)
    elseif k == 'size' and (v < 1 or v % 1 ~= 0) then
      bad[#bad + 1] = ('size should be a whole number of columns or rows, not %s'):format(v)
    else
      M.config[k] = v
    end
  end
  if #bad > 0 then vim.notify('vellum: ' .. table.concat(bad, '; '), vim.log.levels.WARN) end
  browser.max_pixels = M.config.max_pixels
  api.nvim_create_augroup('vellum_auto', { clear = true })
  if M.config.auto_open then
    -- markdown in a real file window: hover popups and picker previews are markdown too
    api.nvim_create_autocmd('BufWinEnter', { group = 'vellum_auto', callback = function(ev)
      if valid() or vim.bo[ev.buf].buftype ~= '' or not mdx.markdown(ev.buf) then return end
      vim.schedule(function()
        if not valid() and api.nvim_get_current_buf() == ev.buf and api.nvim_win_get_config(0).relative == '' then M.open() end
      end)
    end })
  end
end

function M.open()
  if valid() then return end
  S = { src = api.nvim_get_current_buf(), buf = api.nvim_create_buf(false, true), anchors = {}, rows = {}, margin = 0 }
  vim.bo[S.buf].bufhidden = 'wipe'
  api.nvim_buf_set_name(S.buf, 'vellum://preview')
  -- `tab = true`: the preview takes a tab of its own, not a place beside the
  -- source. tabnew leaves one empty window, and the preview buffer goes into
  -- it, so the tab holds nothing else and closing the preview closes the tab.
  local from = api.nvim_get_current_win()
  if M.config.tab then
    vim.cmd('tabnew')
    S.win = api.nvim_get_current_win()
    api.nvim_win_set_buf(S.win, S.buf)
    -- `tab = true` asks to see the preview, so :Vellum jumps to its tab; gT brings the source back
    api.nvim_set_current_win(S.win)
  else
    local side = M.config.split == 'left' or M.config.split == 'right'
    S.win = api.nvim_open_win(S.buf, false, {
      split = M.config.split, win = from, width = side and M.config.size or nil, height = not side and M.config.size or nil,
    })
  end
  local wo = vim.wo[S.win][0]
  wo.number, wo.relativenumber, wo.signcolumn, wo.foldcolumn, wo.statuscolumn = false, false, 'no', '0', ''
  wo.wrap, wo.list, wo.spell, wo.cursorline, wo.colorcolumn = false, false, false, false, ''
  -- scrolloff would move the topline sync sets, and follow() would echo it back
  wo.fillchars, wo.winfixbuf, wo.scrolloff = 'eob: ', true, 0
  vim.keymap.set('n', 'q', M.close, { buffer = S.buf, desc = 'Close preview' })
  vim.keymap.set('n', '<CR>', function()
    if not M.follow() then M.zoom() end
  end, { buffer = S.buf, desc = 'Follow the link, or zoom the image' })
  vim.keymap.set('n', 'gx', function()
    if not M.follow() then vim.notify('vellum: no link under the cursor', vim.log.levels.INFO) end
  end, { buffer = S.buf, desc = 'Follow the link' })
  if M.config.tab then
    tabkeys(S.buf)
    tabkeys(S.src)
  end
  theme.apply()
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
    if ev.buf == S.buf then
      -- tabbing away overwrote the screen, and kitty placements do not re-anchor to text
      -- reprinted on the way back: re-place what is on screen once this window has redrawn
      replace:start(100, 0, vim.schedule_wrap(function()
        if not valid() then return end
        local again = {}
        for _, row in pairs(S.rows) do
          for _, m in ipairs(row) do
            local id = image.id_of(m[3])
            if id and not again[id] then
              again[id] = true
              image.resend(id)
            end
          end
        end
      end))
    elseif ev.buf ~= S.src and mdx.markdown(ev.buf) then
      S.src = ev.buf
      if M.config.tab then tabkeys(ev.buf) end
      update()
    end
  end)
  -- after every other ColorScheme handler, so a user's own Vellum* colors set
  -- there are in place before merged groups copy them
  au('ColorScheme', vim.schedule_wrap(function()
    if not valid() then return end
    theme.apply()
    render.reset()
    update()
  end))
  -- a re-attached tmux session may sit in a new terminal that lost the images
  au('FocusGained', function()
    image.reset()
    render.reset()
    update()
  end)
  au('WinClosed', function() vim.schedule(M.close) end, { pattern = tostring(S.win) })
  -- a forced `:bwipeout!` takes the preview buffer even while winfixbuf pins its window;
  -- the preview must close with it, not draw onto a wiped buffer id on every edit
  au({ 'BufUnload', 'BufWipeout' }, function(ev)
    if ev.buf == S.buf then vim.schedule(M.close) end
  end)
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
  -- sync reads the current window as the source; the first draw must follow the
  -- source cursor even when the focus is already the preview window
  api.nvim_win_call(from, draw)
end

function M.close()
  api.nvim_clear_autocmds({ group = group })
  settle:stop()
  replace:stop()
  spin:stop()
  wake:stop()
  for _, buf in ipairs({ S.buf, S.src }) do
    if buf and api.nvim_buf_is_valid(buf) then
      for key in pairs(TAB_KEYS) do
        pcall(vim.keymap.del, 'n', key, { buffer = buf })
      end
    end
  end
  if S.win and api.nvim_win_is_valid(S.win) then pcall(api.nvim_win_close, S.win, true) end
  S = {}
end

-- Follow the link under the preview's cursor. False when there is none.
function M.follow()
  local win = vim.fn.bufwinid(S.src)
  if not valid() or win == -1 then return false end
  local row, col = unpack(api.nvim_win_get_cursor(S.win))
  for _, m in ipairs(S.rows[row] or {}) do
    if m[5] and col >= m[1] + S.margin and col < m[2] + S.margin then
      local src = S.src
      local err = links.follow(m[5], S.src, win)
      if err then vim.notify('vellum: ' .. err, vim.log.levels.WARN) end
      if valid() then
        -- another file must be rendered before the preview can scroll to its heading
        if S.src ~= src then draw() end
        -- the cursor moved in the source window, which is not the current one
        api.nvim_win_call(win, function() sync(true) end)
      end
      return true
    end
  end
  return false
end

-- Open the image on the preview's cursor line full-screen. That line follows
-- the source cursor, so this works from either window.
function M.zoom()
  if not valid() then return end
  for _, m in ipairs(S.rows[api.nvim_win_get_cursor(S.win)[1]] or {}) do
    local id = image.id_of(m[3])
    if id then return zoom.open(image.paths[id]) end
  end
  vim.notify('vellum: no image on this line', vim.log.levels.INFO)
end

-- Write the markdown buffer (the current one, or the previewed one when in
-- the preview) to `path`, a .pdf or .html file; by default a PDF beside it.
function M.export(path)
  local buf = api.nvim_get_current_buf()
  if buf == S.buf then buf = S.src end
  if not buf or not mdx.markdown(buf) then
    return vim.notify('vellum: export works on a markdown buffer', vim.log.levels.ERROR)
  end
  local name = api.nvim_buf_get_name(buf)
  path = (path or '') ~= '' and vim.fn.fnamemodify(vim.fn.expand(path), ':p') or name ~= '' and vim.fn.fnamemodify(name, ':p:r') .. '.pdf'
  if not path or not (path:match('%.pdf$') or path:match('%.html$')) then
    return vim.notify('vellum: export to a .pdf or .html file, e.g. :Vellum export notes.pdf', vim.log.levels.ERROR)
  end
  vim.notify('vellum: exporting to ' .. path .. ' …')
  local text = table.concat(mdx.lines(buf), '\n')
  local dir = name ~= '' and vim.fs.dirname(vim.fn.fnamemodify(name, ':p')) or vim.fn.getcwd()
  local kinds = {} -- callout type → its color, as in the preview
  for kind, a in pairs(render.alerts) do kinds[kind:lower()] = a[2]:lower() end
  browser.export({ markdown = text, dir = dir, out = path, kinds = kinds }, function(err)
    if err then
      vim.notify('vellum: export failed: ' .. err, vim.log.levels.ERROR)
    else
      vim.notify('vellum: wrote ' .. path)
    end
  end)
end

function M.toggle()
  if valid() then M.close() else M.open() end
end

return M
