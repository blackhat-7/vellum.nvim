-- Markdown blocks → styled lines for the preview buffer. A line is a list of
-- segments (see inline.lua).
local image = require('vellum.image')
local theme = require('vellum.theme')
local inline = require('vellum.inline')
local media = require('vellum.media')
local code = require('vellum.code')

local ts = vim.treesitter
local strwidth = vim.api.nvim_strwidth
local M = {}

local src = {}
local cache, used = {}, {} -- rendered blocks by (type, width, depth, source text)
local depth = 0 -- list nesting, picks the bullet glyph

function M.reset()
  cache, used = {}, {}
  code.reset()
end

local ZWSP = '\226\128\139' -- zero-width space, see M.render

-- Source text of `node`, minus the container prefixes ("> ", list indent)
-- that tree-sitter marks as block_continuation anywhere inside `from`.
local function text_of(node, from)
  local sr, sc, er, ec = node:range()
  local skip = {}
  local function scan(n)
    for c in n:iter_children() do
      if c:type() == 'block_continuation' then
        local r, _, _, e = c:range()
        skip[r] = e
      elseif from ~= node then
        scan(c)
      end
    end
  end
  if from then scan(from) end
  local out = {}
  for r = sr, er do
    if r < er or ec > 0 then
      local line = src[r + 1] or ''
      out[#out + 1] = line:sub(math.max(r == sr and sc or 0, skip[r] or 0) + 1, r == er and ec or #line)
    end
  end
  return (table.concat(out, '\n'):gsub(ZWSP, ''))
end

local function child(node, type)
  for c in node:iter_children() do
    if c:type() == type then return c end
  end
end

-- Named children that carry content, skipping types matching `skip`.
local function kids(node, skip)
  local out = {}
  for c in node:iter_children() do
    local t = c:type()
    if c:named() and t ~= 'block_continuation' and not (skip and t:match(skip)) then out[#out + 1] = c end
  end
  return out
end

-- New hl list: `g` underneath `hl`.
local function under(hl, g)
  if not g then return hl end
  if type(hl) == 'string' then return { g, hl } end
  return { g, unpack(hl or {}) }
end

-- A gradient rule of `char`: strongest at the start, or at the center if `sym`.
local function fade(width, char, group, sym)
  local line, n = {}, theme.FADE
  for i = 0, width - 1 do
    local t = sym and math.abs((i + 0.5) / width * 2 - 1) or i / width
    local hl = group .. math.max(1, n - math.floor(t * n))
    local last = line[#line]
    if last and last[2] == hl then last[1] = last[1] .. char else line[#line + 1] = { char, hl } end
  end
  return line
end

---------------------------------------------------------------- blocks

local R = {}
local render_block

local function heading_level(node)
  if node:type() == 'section' then node = node:named_child(0) end
  local t = node and node:type()
  if t ~= 'atx_heading' and t ~= 'setext_heading' then return nil end
  -- not child(0) / last child: a block_continuation can sit on either side
  for c in node:iter_children() do
    local l = c:type():match('^atx_h(%d)_marker$') or c:type():match('^setext_h(%d)_underline$')
    if l then return tonumber(l) end
  end
end

-- Render `nodes` stacked, blank line between them unless `tight`.
-- Anchors { src_row, src_rows, out_line, out_lines } are relative to `base`.
local function blocks(nodes, width, base, tight)
  local lines, anchors = {}, {}
  for _, n in ipairs(nodes) do
    local l, a = render_block(n, width)
    if #l > 0 then
      if #lines > 0 and not tight then
        lines[#lines + 1] = {}
        if (heading_level(n) or 9) <= 2 then lines[#lines + 1] = {} end
      end
      local off, row = #lines, n:start() - base
      for _, x in ipairs(a) do anchors[#anchors + 1] = { x[1] + row, x[2], x[3] + off, x[4] } end
      vim.list_extend(lines, l)
    end
  end
  return lines, anchors
end

function render_block(node, width)
  local t = node:type()
  local fn = R[t] or R.fallback
  if t == 'section' or t == 'document' then return fn(node, width) end
  local key = table.concat({ t, width, depth, text_of(node) }, '\0')
  local hit = used[key] or cache[key]
  if hit then
    used[key] = hit
    return hit[1], hit[2]
  end
  local v = media.pending
  local lines, anchors = fn(node, width)
  if not anchors then
    local sr, _, er, ec = node:range()
    anchors = { { 0, math.max(1, er - sr + (ec > 0 and 1 or 0)), 0, #lines } }
  end
  if v == media.pending then used[key] = { lines, anchors } end
  return lines, anchors
end

function R.document(node, width) return blocks(kids(node), width, (node:start())) end
R.section = R.document

local function heading(level, text, width)
  local segs = inline.parse(vim.trim((text:gsub('%s+#+%s*$', ''))), 'VellumH' .. level)
  if level > 1 then
    local out = inline.wrap(segs, width)
    if level == 2 then out[#out + 1] = fade(width, '─', 'VellumFadeMuted') end
    return out
  end
  -- H1: a tall tinted band with a gradient edge underneath
  local pad = { { string.rep(' ', width), 'VellumH1Band' } }
  local out = { pad }
  for _, l in ipairs(inline.wrap(segs, width - 4)) do
    local line = { { '  ', 'VellumH1Band' } }
    for _, s in ipairs(l) do line[#line + 1] = { s[1], under(s[2], 'VellumH1Band') } end
    line[#line + 1] = { string.rep(' ', width - 2 - inline.width(l)), 'VellumH1Band' }
    out[#out + 1] = line
  end
  out[#out + 1] = pad
  out[#out + 1] = fade(width, '▔', 'VellumFade')
  return out
end

function R.atx_heading(node, width)
  local inl = child(node, 'inline')
  return heading(heading_level(node), inl and text_of(inl, inl) or '', width)
end

function R.setext_heading(node, width)
  local p = child(node, 'paragraph')
  local inl = p and child(p, 'inline')
  return heading(heading_level(node), inl and text_of(inl, inl) or '', width)
end

-- "[^label]: text" lines, which tree-sitter sees as one plain paragraph.
local function footnotes(text, width)
  local defs = {}
  for line in (text .. '\n'):gmatch('(.-)\n') do
    local label, body = line:match('^%[%^([^%]]+)%]:%s*(.*)$')
    if label then
      defs[#defs + 1] = { inline.note(label), body }
    else
      defs[#defs][2] = defs[#defs][2] .. '\n' .. line
    end
  end
  local out = {}
  for _, d in ipairs(defs) do
    local mw = strwidth(d[1]) + 1
    for k, l in ipairs(inline.wrap(inline.parse(d[2], 'VellumMuted'), width - mw)) do
      out[#out + 1] = { { k == 1 and d[1] .. ' ' or string.rep(' ', mw), k == 1 and 'VellumLink' or nil }, unpack(l) }
    end
  end
  return out
end

function R.paragraph(node, width)
  local inl = child(node, 'inline')
  local text = inl and text_of(inl, inl) or text_of(node, node)
  if text:match('^%[%^[^%]]+%]:') then return footnotes(text, width) end
  return inline.wrap(inline.parse(text), width)
end

function R.fenced_code_block(node, width)
  local info = child(node, 'info_string')
  local lang = info and text_of(info):match('^%s*([%w_+#.-]+)') -- "json,title=x" and "{r}" carry more than a language
  local body = child(node, 'code_fence_content')
  local text = body and text_of(body, node) or ''
  if lang and lang:lower() == 'mermaid' and image.supported then return code.diagram(text, width, (node:start())) end
  return code.panel(text, lang, width)
end

function R.indented_code_block(node, width)
  local lines = vim.split(text_of(node, node), '\n')
  for i, l in ipairs(lines) do lines[i] = l:gsub('^ ? ? ? ?', '') end
  while #lines > 1 and lines[#lines]:match('^%s*$') do lines[#lines] = nil end
  return code.panel(table.concat(lines, '\n'), nil, width)
end

local ALERTS = {
  NOTE = { '󰋽', 'Note' }, TIP = { '󰌶', 'Tip' }, IMPORTANT = { '󰅾', 'Important' },
  WARNING = { '󰀪', 'Warning' }, CAUTION = { '󰳦', 'Caution' },
}

function R.block_quote(node, width)
  local body, head, alert = kids(node, '^block_quote_marker$'), {}, nil
  local p = body[1] and body[1]:type() == 'paragraph' and child(body[1], 'inline')
  if p then
    local kind, rest = text_of(p, p):match('^%[!(%a+)%]%s*(.*)$')
    alert = kind and ALERTS[kind:upper()]
    if alert then
      table.remove(body, 1)
      if rest ~= '' then head = inline.wrap(inline.parse(rest), width - 2) end
    end
  end
  local lines, anchors = blocks(body, width - 2, (node:start()))
  local bar = alert and ('Vellum' .. alert[2]) or 'VellumQuoteBar'
  local inner = {}
  if alert then
    inner[1] = { { alert[1] .. '  ' .. alert[2], bar } }
    vim.list_extend(inner, head)
    if #head > 0 and #lines > 0 then inner[#inner + 1] = {} end
  end
  for _, a in ipairs(anchors) do a[3] = a[3] + #inner end
  vim.list_extend(inner, lines)
  local out = {}
  for i, l in ipairs(inner) do
    local line = { { '▎ ', bar } }
    for _, s in ipairs(l) do
      -- plain quotes dim their prose; code keeps its own colors
      local hl = s[2]
      if not alert and not s[3] then hl = under(hl, 'VellumQuote') end
      line[#line + 1] = { s[1], hl, s[3] }
    end
    out[i] = line
  end
  return out, #anchors > 0 and anchors or nil
end

local BULLETS = { '•', '◦', '▪', '▫' }

function R.list(node, width)
  depth = depth + 1
  local items = kids(node)
  local marker = items[1] and items[1]:named_child(0)
  local ordered = marker and marker:type():match('_dot$') or marker and marker:type():match('_parenthesis$')
  local start = ordered and tonumber(text_of(marker):match('%d+')) or 1
  local mw = ordered and #tostring(start + #items - 1) + 2 or 2
  local lines, anchors = {}, {}
  for i, item in ipairs(items) do
    local label, hl = BULLETS[(depth - 1) % #BULLETS + 1], 'VellumBullet'
    if ordered then label = (start + i - 1) .. '.' end
    if child(item, 'task_list_marker_checked') then
      label, hl = '󰄵', 'VellumDone'
    elseif child(item, 'task_list_marker_unchecked') then
      label, hl = '󰄱', 'VellumTodo'
    end
    local l, a = blocks(kids(item, '_marker'), width - mw, node:start(), true)
    local off = #lines
    for _, x in ipairs(a) do
      x[3] = x[3] + off
      anchors[#anchors + 1] = x
    end
    local indent = { string.rep(' ', mw) }
    local first = { { string.rep(' ', mw - 1 - strwidth(label)) .. label .. ' ', hl } }
    if #l == 0 then lines[#lines + 1] = first end
    for k, line in ipairs(l) do
      local out = { k == 1 and first[1] or indent }
      vim.list_extend(out, line)
      lines[#lines + 1] = out
    end
    -- a blank source line after an item makes the list loose
    local _, _, er, ec = item:range()
    local last = ec > 0 and er or er - 1
    if i < #items and (src[last + 1] or ''):match('^[%s>]*$') then lines[#lines + 1] = {} end
  end
  depth = depth - 1
  return lines, #anchors > 0 and anchors or nil
end

function R.pipe_table(node, width)
  local rows, align = {}, {}
  for r in node:iter_children() do
    local t = r:type()
    if t == 'pipe_table_delimiter_row' then
      for c in r:iter_children() do
        if c:type() == 'pipe_table_delimiter_cell' then
          local left, right = child(c, 'pipe_table_align_left'), child(c, 'pipe_table_align_right')
          align[#align + 1] = left and right and 'center' or right and 'right' or 'left'
        end
      end
    elseif t == 'pipe_table_header' or t == 'pipe_table_row' then
      local cells = {}
      for c in r:iter_children() do
        if c:type() == 'pipe_table_cell' then
          local segs = inline.parse(vim.trim(text_of(c)))
          for _, s in ipairs(segs) do s.image = nil end -- a block picture would burst the cell
          cells[#cells + 1] = segs
        end
      end
      rows[#rows + 1] = cells
    end
  end
  local n = #align
  local cw, least, total = {}, {}, 0
  for c = 1, n do
    cw[c], least[c] = 1, 1
    for _, row in ipairs(rows) do
      cw[c] = math.max(cw[c], inline.width(row[c] or {}))
      for _, s in ipairs(row[c] or {}) do
        for word in s[1]:gmatch('%S+') do least[c] = math.max(least[c], math.min(30, strwidth(word))) end
      end
    end
    total = total + cw[c]
  end
  -- shrink the widest column until the table fits, never splitting a word;
  -- a table that still does not fit scrolls sideways, as on GitHub
  while total > width - 3 * n - 1 do
    local widest
    for c = 1, n do
      if cw[c] > least[c] and (not widest or cw[c] > cw[widest]) then widest = c end
    end
    if not widest then break end
    cw[widest], total = cw[widest] - 1, total - 1
  end
  local B = 'VellumBorder'
  local function rule(l, m, r)
    local parts = {}
    for c = 1, n do parts[c] = string.rep('─', cw[c] + 2) end
    return { { l .. table.concat(parts, m) .. r, B } }
  end
  local out = { rule('╭', '┬', '╮') }
  for i, row in ipairs(rows) do
    local fill = i == 1 and 'VellumTableHead' or (i % 2 == 1 and 'VellumTableRow' or nil)
    local cells, h = {}, 1
    for c = 1, n do
      cells[c] = inline.wrap(row[c] or {}, cw[c])
      h = math.max(h, #cells[c])
    end
    for k = 1, h do
      local line = { { '│', B } }
      for c = 1, n do
        local segs = cells[c][k] or {}
        local pad = cw[c] - inline.width(segs)
        local left = align[c] == 'right' and pad or align[c] == 'center' and math.floor(pad / 2) or 0
        line[#line + 1] = { string.rep(' ', left + 1), fill }
        for _, s in ipairs(segs) do line[#line + 1] = { s[1], under(s[2], fill) } end
        line[#line + 1] = { string.rep(' ', pad - left + 1), fill }
        line[#line + 1] = { '│', B }
      end
      out[#out + 1] = line
    end
    if i == 1 then out[#out + 1] = rule('├', '┼', '┤') end
  end
  out[#out + 1] = rule('╰', '┴', '╯')
  return out
end

function R.thematic_break(_, width) return { fade(width, '─', 'VellumFade', true) } end

-- HTML text as lines: tags go, except <img> and <br>, which the inline
-- parser renders. Only tags: "<40 words" is text.
local function html(text, width, hl)
  text = vim.trim((text:gsub('</?%a[^>]*>', function(tag)
    return (tag:match('^<[iI][mM][gG]') or tag:match('^<[bB][rR]')) and tag or ''
  end)))
  return text == '' and {} or inline.wrap(inline.parse(text, hl), width)
end

function R.html_block(node, width)
  local text = text_of(node, node)
  if text:match('^%s*<!%-%-') then return {} end
  -- <details> shows open, as on GitHub once clicked: a marked summary line,
  -- then the body, which tree-sitter parses as the blocks that follow
  local before, summary, after = text:match('^(.-)<summary[^>]*>(.-)</summary>(.*)$')
  if not summary then return html(text, width) end
  local out = html(before, width)
  vim.list_extend(out, html('▾ ' .. summary, width, 'VellumBold'))
  return vim.list_extend(out, html(after, width))
end

function R.minus_metadata(node, width)
  return code.panel((text_of(node):gsub('^%-%-%-\n', ''):gsub('\n?%-%-%-%s*$', '')), 'yaml', width)
end

-- hidden, except "[^1]: word", which is a one-word footnote
function R.link_reference_definition(node, width)
  local text = text_of(node, node)
  return text:match('^%[%^[^%]]+%]:') and footnotes(text, width) or {}
end

function R.fallback(node, width) return inline.wrap({ { text_of(node, node), { 'VellumMuted' } } }, width) end

---------------------------------------------------------------- entry

-- Render buffer `buf` for a window `win_width` wide. Returns buffer lines,
-- per-row marks { col, end_col, group, priority } (columns exclude the left
-- margin), the margin width, and anchors for scroll sync.
function M.render(buf, win_width, max_width)
  src = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  media.dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':p:h')
  local width = math.max(20, math.min(win_width - 4, max_width))
  local margin = string.rep(' ', math.max(0, math.floor((win_width - width) / 2)))
  depth = 0
  local root = ts.get_parser(buf, 'markdown'):parse()[1]:root()
  if root:has_error() then
    -- tree-sitter-markdown gives up on table rows with an empty cell written
    -- "||", or with every cell empty ("|  |  |"), dropping rows GitHub shows.
    -- Outside code, space out "||" and give all-empty cells an invisible
    -- character (text_of strips it), then parse that.
    local fixed = false
    for i, l in ipairs(src) do
      local node = l:match('^[%s>]*|') and root:named_descendant_for_range(i - 1, 0, i - 1, 0)
      if node and not node:type():match('code') then
        local was = l
        repeat
          local prev = l
          l = l:gsub('||', '| |')
        until l == prev
        local body, tail = l:match('^([%s>]*|[%s|]*)(|%s*)$')
        if body then l = body:gsub('|(%s*)', '|%1' .. ZWSP) .. tail end
        if l ~= was then src[i], fixed = l, true end
      end
    end
    if fixed then root = ts.get_string_parser(table.concat(src, '\n'), 'markdown'):parse()[1]:root() end
  end
  local body, anchors = blocks(kids(root), width, 0)
  cache, used = used, {}
  local text, rows = { '' }, { {} } -- a blank first line for breathing room
  for i, line in ipairs(body) do
    -- flattened once per line object; cached blocks reuse theirs
    if not line.flat then
      local parts, marks, col = {}, {}, 0
      for _, s in ipairs(line) do
        local len = #s[1]
        local group = s[2] and theme.merge(s[2])
        if group and len > 0 then marks[#marks + 1] = { col, col + len, group, 100 } end
        for k, m in ipairs(s[3] or {}) do marks[#marks + 1] = { col + m[1], col + m[2], m[3], 100 + k } end
        parts[#parts + 1] = s[1]
        col = col + len
      end
      line.flat = { table.concat(parts), marks }
    end
    text[i + 1] = margin .. line.flat[1]
    rows[i + 1] = line.flat[2]
  end
  for _, a in ipairs(anchors) do a[3] = a[3] + 1 end
  return text, rows, #margin, anchors
end

return M
