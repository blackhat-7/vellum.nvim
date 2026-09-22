-- Markdown → styled lines for the preview buffer.
-- A line is a list of segments { text, hl, marks }: hl is nil, a group, or a
-- list of groups (merged, later wins); marks are extra { start, end, group }
-- byte ranges inside the segment (syntax highlighting in code blocks).
local image = require('vellum.image')
local browser = require('vellum.browser')
local theme = require('vellum.theme')

local ts = vim.treesitter
local strwidth = vim.api.nvim_strwidth
local M = {}

local src, dir = {}, '.'
local cache, used = {}, {} -- rendered blocks by (type, width, depth, source text)
local volatile = 0 -- bumped by output that changes on its own (pending diagrams), which must not be cached
local last_diagram = {} -- source row → last ready diagram, shown while an edit re-renders
local depth = 0 -- list nesting, picks the bullet glyph

function M.reset() cache, used, last_diagram = {}, {}, {} end

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
  return table.concat(out, '\n')
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

local function segs_width(segs)
  local w = 0
  for _, s in ipairs(segs) do
    if s[1] ~= '\n' then w = w + strwidth(s[1]) end
  end
  return w
end

---------------------------------------------------------------- inline

local ENTITIES = {
  amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' ', copy = '©', reg = '®',
  trade = '™', mdash = '—', ndash = '–', hellip = '…', rarr = '→', larr = '←', times = '×',
}

local SUPERSCRIPT = { ['0'] = '⁰', ['1'] = '¹', ['2'] = '²', ['3'] = '³', ['4'] = '⁴', ['5'] = '⁵', ['6'] = '⁶', ['7'] = '⁷', ['8'] = '⁸', ['9'] = '⁹' }

-- Footnote label as shown: superscript digits, else [label].
local function note(label)
  return label:match('^%d+$') and (label:gsub('%d', SUPERSCRIPT)) or '[' .. label .. ']'
end

-- Inline markdown → segments. A { '\n' } segment is a hard line break.
local function inline(text, hl)
  local segs = {}
  local function with(hls, g)
    local t = { unpack(hls) }
    t[#t + 1] = g
    return t
  end
  local function push(s, hls)
    if s == '' then return end
    s = s:gsub('\n', ' ')
    local i = 1
    if not (vim.tbl_contains(hls, 'VellumLink') or vim.tbl_contains(hls, 'VellumCode')) then
      -- GFM autolinks bare URLs
      for a, url, b in s:gmatch('()(https?://[^%s<>]*[^%s<>%.,;:!%?%)%]\'"])()') do
        if a > i then segs[#segs + 1] = { s:sub(i, a - 1), hls } end
        segs[#segs + 1] = { url, with(hls, 'VellumLink') }
        i = b
      end
    end
    if i <= #s then segs[#segs + 1] = { s:sub(i), hls } end
  end
  local function span(n) return select(3, n:start()), select(3, n:end_()) end
  local function walk(node, hls)
    local pos, stop = span(node)
    -- anonymous children are punctuation ("/", ":"); they stay in the text runs
    for c in node:iter_children() do
      if not c:named() then goto continue end
      local cs, ce = span(c)
      push(text:sub(pos + 1, cs), hls)
      pos = ce
      local t = c:type()
      if t == 'emphasis' then
        walk(c, with(hls, 'VellumItalic'))
      elseif t == 'strong_emphasis' then
        walk(c, with(hls, 'VellumBold'))
      elseif t == 'strikethrough' then
        walk(c, with(hls, 'VellumStrike'))
      elseif t == 'code_span' then
        local code = text:sub(cs + 1, ce):gsub('^`+', ''):gsub('`+$', ''):gsub('\n', ' ')
        if code:match('^ .* $') then code = code:sub(2, -2) end
        segs[#segs + 1] = { ' ' .. code .. ' ', with(hls, 'VellumCode') }
      elseif t == 'inline_link' or t == 'full_reference_link' or t == 'collapsed_reference_link' then
        local label = child(c, 'link_text')
        if label then walk(label, with(hls, 'VellumLink')) end
      elseif t == 'image' then
        local alt = child(c, 'image_description')
        segs[#segs + 1] = { '󰋩 ' .. (alt and text:sub(select(3, alt:start()) + 1, select(3, alt:end_())) or 'image'), with(hls, 'VellumMuted') }
      elseif t == 'uri_autolink' or t == 'email_autolink' then
        segs[#segs + 1] = { text:sub(cs + 2, ce - 1), with(hls, 'VellumLink') }
      elseif t == 'backslash_escape' then
        push(text:sub(cs + 2, ce), hls)
      elseif t == 'entity_reference' or t == 'numeric_character_reference' then
        local e = text:sub(cs + 1, ce)
        local n = tonumber(e:match('^&#[xX](%x+);$') or '', 16) or tonumber(e:match('^&#(%d+);$') or '')
        push(n and vim.fn.nr2char(n) or ENTITIES[e:sub(2, -2)] or e, hls)
      elseif t == 'hard_line_break' then
        segs[#segs + 1] = { '\n' }
      elseif t == 'html_tag' then
        if text:sub(cs + 1, ce):match('^<[bB][rR]') then segs[#segs + 1] = { '\n' } end
      elseif t == 'shortcut_link' then -- "[x]" without a definition is literal text, "[^x]" a footnote
        local label = text:sub(cs + 1, ce):match('^%[%^([^%]]+)%]$')
        if label then segs[#segs + 1] = { note(label), with(hls, 'VellumLink') } else push(text:sub(cs + 1, ce), hls) end
      elseif not t:match('delimiter$') then
        walk(c, hls)
      end
      ::continue::
    end
    push(text:sub(pos + 1, stop), hls)
  end
  walk(ts.get_string_parser(text, 'markdown_inline'):parse()[1]:root(), hl and { hl } or {})
  return segs
end

-- Greedy word wrap. A word may span segments ("**bold**,"), so breaks happen
-- only at whitespace; a word wider than the line is split by characters.
local function wrap(segs, width)
  local lines, line, w = {}, {}, 0
  local word, ww, space = {}, 0, nil
  local function newline() lines[#lines + 1], line, w = line, {}, 0 end
  local function put(text, hl, cw)
    local last = line[#line]
    if last and last[2] == hl then last[1] = last[1] .. text else line[#line + 1] = { text, hl } end
    w = w + cw
  end
  local function flush()
    if ww == 0 then return end
    if w > 0 and w + (space and 1 or 0) + ww > width then newline() end
    if space and w > 0 then put(' ', space, 1) end
    for _, p in ipairs(word) do
      if ww <= width then
        put(p[1], p[2], strwidth(p[1]))
      else
        for ch in p[1]:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
          local cw = strwidth(ch)
          if w > 0 and w + cw > width then newline() end
          put(ch, p[2], cw)
        end
      end
    end
    word, ww, space = {}, 0, nil
  end
  for _, s in ipairs(segs) do
    if s[1] == '\n' then
      flush()
      newline()
      space = nil
    else
      local t, i = s[1], 1
      while i <= #t do
        local a, b = t:find('^%s+', i)
        if a then
          flush()
          space = space or s[2] or {}
        else
          a, b = t:find('^%S+', i)
          local piece = t:sub(a, b)
          word[#word + 1] = { piece, s[2] }
          ww = ww + strwidth(piece)
        end
        i = b + 1
      end
    end
  end
  flush()
  if #line > 0 or #lines == 0 then newline() end
  return lines
end

---------------------------------------------------------------- pieces

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

-- An image centered in `width`; `density` is image pixels per CSS pixel.
local function picture(file, pw, ph, width, density)
  local cw, ch = image.cell()
  -- scale so 16px diagram text lands near terminal text size
  local cols = math.max(1, math.min(width, math.ceil(pw / density * ch / 24 / cw)))
  local rows = math.max(1, math.floor(cols * cw * ph / pw / ch + 0.5))
  if rows > image.max_rows then
    rows = image.max_rows
    cols = math.max(1, math.min(width, math.floor(rows * ch * pw / ph / cw)))
  end
  local pad = { string.rep(' ', math.floor((width - cols) / 2)) }
  local out = {}
  for i, l in ipairs(image.lines(file, cols, rows)) do out[i] = { pad, l[1] } end
  return out
end

-- Lines showing image `src` (local path or http(s) URL), or nil to fall back
-- to its alt text. PNGs go straight to the terminal; other formats and remote
-- images go through the browser.
local function picture_of(src, width)
  if not image.supported then return nil end
  local remote, version = src:match('^https?://'), os.date('%F') -- remote images refresh daily
  if not remote then
    if src:match('^%a[%w+.-]*:') then return nil end
    src = vim.fs.normalize(src:sub(1, 1) == '/' and src or dir .. '/' .. src)
    local stat = vim.uv.fs_stat(src)
    if not stat or stat.type ~= 'file' then return nil end
    if src:lower():match('%.png$') then
      local pw, ph = image.png_size(src)
      return pw and picture(src, pw, ph, width, 1)
    end
    version = stat.mtime.sec .. '.' .. stat.size
  end
  local state, file, size = browser.image(src, version)
  if state == 'ready' then return picture(file, size[1], size[2], width, 2) end
  if state == 'pending' then volatile = volatile + 1 end
  return nil
end

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
local function code_panel(code, lang, width, label, err)
  code = code:gsub('\t', '    ')
  local marks = lang and highlights(code, lang) or {}
  local inner, bg = math.max(1, width - 4), 'VellumCodeBg'
  label = label or lang or ''
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
      for _, l in ipairs(wrap({ { text, { bg, 'VellumError' } } }, inner)) do
        table.insert(l, 1, { '  ', bg })
        l[#l + 1] = { string.rep(' ', math.max(0, inner - segs_width(l) + 2) + 2), bg }
        out[#out + 1] = l
      end
    end
  end
  out[#out + 1] = { { string.rep(' ', width), bg } }
  return out
end

local function diagram(code, width, row)
  local state, a, b = browser.diagram(code, theme)
  if state == 'ready' then
    last_diagram[row] = picture(a, b[1], b[2], width, 2)
    return last_diagram[row]
  elseif state == 'error' then
    return code_panel(code, 'mermaid', width, nil, a)
  end
  volatile = volatile + 1
  return last_diagram[row] or code_panel(code, 'mermaid', width, 'rendering…')
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
  local v = volatile
  local lines, anchors = fn(node, width)
  if not anchors then
    local sr, _, er, ec = node:range()
    anchors = { { 0, math.max(1, er - sr + (ec > 0 and 1 or 0)), 0, #lines } }
  end
  if v == volatile then used[key] = { lines, anchors } end
  return lines, anchors
end

function R.document(node, width) return blocks(kids(node), width, (node:start())) end
R.section = R.document

local function heading(level, text, width)
  local segs = inline(vim.trim((text:gsub('%s+#+%s*$', ''))), 'VellumH' .. level)
  if level > 1 then
    local out = wrap(segs, width)
    if level == 2 then out[#out + 1] = fade(width, '─', 'VellumFadeMuted') end
    return out
  end
  -- H1: a tall tinted band with a gradient edge underneath
  local pad = { { string.rep(' ', width), 'VellumH1Band' } }
  local out = { pad }
  for _, l in ipairs(wrap(segs, width - 4)) do
    local line = { { '  ', 'VellumH1Band' } }
    for _, s in ipairs(l) do line[#line + 1] = { s[1], under(s[2], 'VellumH1Band') } end
    line[#line + 1] = { string.rep(' ', width - 2 - segs_width(l)), 'VellumH1Band' }
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
      defs[#defs + 1] = { note(label), body }
    else
      defs[#defs][2] = defs[#defs][2] .. '\n' .. line
    end
  end
  local out = {}
  for _, d in ipairs(defs) do
    local mw = strwidth(d[1]) + 1
    for k, l in ipairs(wrap(inline(d[2], 'VellumMuted'), width - mw)) do
      out[#out + 1] = { { k == 1 and d[1] .. ' ' or string.rep(' ', mw), k == 1 and 'VellumLink' or nil }, unpack(l) }
    end
  end
  return out
end

function R.paragraph(node, width)
  local inl = child(node, 'inline')
  local text = inl and text_of(inl, inl) or text_of(node, node)
  if text:match('^%[%^[^%]]+%]:') then return footnotes(text, width) end
  local path = text:match('^%s*!%[[^%]]*%]%(%s*<?([^%s>)]+)>?[^)]*%)%s*$')
  return path and picture_of(path, width) or wrap(inline(text), width)
end

function R.fenced_code_block(node, width)
  local info = child(node, 'info_string')
  local lang = info and text_of(info):match('^%s*([^%s{]+)')
  local body = child(node, 'code_fence_content')
  local code = body and text_of(body, node) or ''
  if lang and lang:lower() == 'mermaid' and image.supported then return diagram(code, width, (node:start())) end
  return code_panel(code, lang, width)
end

function R.indented_code_block(node, width)
  local lines = vim.split(text_of(node, node), '\n')
  for i, l in ipairs(lines) do lines[i] = l:gsub('^ ? ? ? ?', '') end
  while #lines > 1 and lines[#lines]:match('^%s*$') do lines[#lines] = nil end
  return code_panel(table.concat(lines, '\n'), nil, width)
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
      if rest ~= '' then head = wrap(inline(rest), width - 2) end
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
        if c:type() == 'pipe_table_cell' then cells[#cells + 1] = inline(vim.trim(text_of(c))) end
      end
      rows[#rows + 1] = cells
    end
  end
  local n = #align
  local cw, total = {}, 0
  for c = 1, n do
    cw[c] = 1
    for _, row in ipairs(rows) do cw[c] = math.max(cw[c], segs_width(row[c] or {})) end
    total = total + cw[c]
  end
  -- shrink the widest column until the table fits; cells then wrap
  while total > width - 3 * n - 1 do
    local widest = 1
    for c = 2, n do if cw[c] > cw[widest] then widest = c end end
    if cw[widest] <= 4 then break end
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
      cells[c] = wrap(row[c] or {}, cw[c])
      h = math.max(h, #cells[c])
    end
    for k = 1, h do
      local line = { { '│', B } }
      for c = 1, n do
        local segs = cells[c][k] or {}
        local pad = cw[c] - segs_width(segs)
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

function R.html_block(node, width)
  local text = text_of(node, node)
  if text:match('^%s*<!%-%-') then return {} end
  local img = text:match('<img[^>]-src="([^"]+)"')
  local shown = img and picture_of(img, width)
  if shown then return shown end
  text = vim.trim((text:gsub('<[^>]*>', '')))
  return text == '' and {} or wrap(inline(text), width)
end

function R.minus_metadata(node, width)
  return code_panel((text_of(node):gsub('^%-%-%-\n', ''):gsub('\n?%-%-%-%s*$', '')), 'yaml', width)
end

-- hidden, except "[^1]: word", which is a one-word footnote
function R.link_reference_definition(node, width)
  local text = text_of(node, node)
  return text:match('^%[%^[^%]]+%]:') and footnotes(text, width) or {}
end

function R.fallback(node, width) return wrap({ { text_of(node, node), { 'VellumMuted' } } }, width) end

---------------------------------------------------------------- entry

-- Render buffer `buf` for a window `win_width` wide. Returns buffer lines,
-- per-row marks { col, end_col, group, priority } (columns exclude the left
-- margin), the margin width, and anchors for scroll sync.
function M.render(buf, win_width, max_width)
  src = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':p:h')
  local width = math.max(20, math.min(win_width - 4, max_width))
  local margin = string.rep(' ', math.max(0, math.floor((win_width - width) / 2)))
  depth = 0
  local body, anchors = blocks(kids(ts.get_parser(buf, 'markdown'):parse()[1]:root()), width, 0)
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
