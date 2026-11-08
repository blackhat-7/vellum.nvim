-- Code blocks: shaded panels with tree-sitter syntax colors, and mermaid
-- and D2 diagrams rendered to images.
local image = require('vellum.image')
local browser = require('vellum.browser')
local theme = require('vellum.theme')
local inline = require('vellum.inline')
local media = require('vellum.media')

local ts = vim.treesitter
local strwidth = vim.api.nvim_strwidth
local M = {}

local last_diagram = {} -- source row → last ready diagram, shown while an edit re-renders

-- A loader that flashes for a fast render looks worse than none, so it shows
-- only once the wait is noticeable. The preview resets these before a draw and
-- reads them after (init.lua): M.loading, a loader is shown, so it turns the
-- spinner; M.due, the vim.uv.now() when the next one is due, to draw again then.
M.SPINNER = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local SPINNER_AFTER, BADGE_AFTER = 400, 1000

local function due(elapsed, after)
  if elapsed >= after then
    M.loading = true
    return true
  end
  M.due = math.min(M.due or math.huge, vim.uv.now() + after - elapsed)
  return false
end

function M.reset() last_diagram = {} end

-- Syntax highlight ranges per 0-based row: { { start, end, group }, ... }.
local function highlights(code, lang)
  local ft = vim.filetype.match({ filename = 'x.' .. lang }) or lang
  local ok, parser = pcall(ts.get_string_parser, code, ts.language.get_lang(ft) or ft)
  local query = ok and ts.query.get(parser:lang(), 'highlights')
  local marks = {}
  if not query then return marks end
  local lines = vim.split(code, '\n')
  for id, node in query:iter_captures(parser:parse()[1]:root(), code) do
    local name = query.captures[id]
    if not name:match('^_') and not name:match('spell$') then
      local sr, sc, er, ec = node:range()
      for r = sr, er do
        marks[r] = marks[r] or {}
        table.insert(marks[r], { r == sr and sc or 0, r == er and ec or #(lines[r + 1] or ''), '@' .. name .. '.' .. parser:lang() })
      end
    end
  end
  return marks
end

-- A shaded code panel with the language as a label, lines wrapped to fit.
function M.panel(code, lang, width, label, err)
  code = code:gsub('\t', '    ')
  local marks = lang and highlights(code, lang) or {}
  local inner, bg = math.max(1, width - 4), 'VellumCodeBg'
  label = vim.fn.strcharpart(label or lang or '', 0, math.max(0, width - 4))
  local out = { { { string.rep(' ', math.max(0, width - strwidth(label) - 2)), bg }, { label, 'VellumCodeLabel' }, { '  ', bg } } }
  for r, text in ipairs(vim.split(code, '\n')) do
    local a = 1
    repeat
      local pos, w = a, 0
      while pos <= #text do
        local ch = text:match('^[%z\1-\127\194-\244][\128-\191]*', pos) or text:sub(pos, pos)
        local cw = strwidth(ch)
        if w + cw > inner and pos > a then break end
        w, pos = w + cw, pos + #ch
      end
      local cm = {}
      for _, m in ipairs(marks[r - 1] or {}) do
        local s, e = math.max(m[1], a - 1), math.min(m[2], pos - 1)
        if s < e then cm[#cm + 1] = { s - a + 1, e - a + 1, m[3] } end
      end
      out[#out + 1] = { { '  ', bg }, { text:sub(a, pos - 1), bg, cm }, { string.rep(' ', math.max(0, inner - w) + 2), bg } }
      a = pos
    until a > #text
  end
  if err then
    for _, text in ipairs(vim.split('✗ ' .. err, '\n')) do
      for _, l in ipairs(inline.wrap({ { text, { bg, 'VellumError' } } }, inner)) do
        table.insert(l, 1, { '  ', bg })
        l[#l + 1] = { string.rep(' ', math.max(0, inner - inline.width(l) + 2) + 2), bg }
        out[#out + 1] = l
      end
    end
  end
  out[#out + 1] = { { string.rep(' ', width), bg } }
  return out
end

-- A diagram in `lang`, 'mermaid' or 'd2', as a picture; its code while it
-- first renders, or with the error when it cannot.
function M.diagram(code, width, row, lang)
  if image.problem() then return M.panel(code, lang, width, nil, image.problem()) end
  local state, a, b = browser.diagram(code, theme, lang, media.dir)
  if state == 'ready' then
    last_diagram[row] = media.picture(a, b[1], b[2], width, b[3])
    return last_diagram[row]
  elseif state == 'error' then
    return M.panel(code, lang, width, nil, a)
  end
  local last = last_diagram[row]
  if not last then
    if not due(a, SPINNER_AFTER) then return M.panel(code, lang, width) end
    local out = M.panel(code, lang, width, M.SPINNER[1] .. ' rendering…')
    out[1][2][2] = 'VellumSpinner' -- the preview turns its first glyph (init.lua)
    return out
  end
  -- an edit keeps the old picture, badged once the wait is noticeable
  return due(a, BADGE_AFTER) and media.badge(last, ' ' .. M.SPINNER[1] .. ' updating ') or last
end

return M
