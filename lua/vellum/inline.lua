-- Inline markdown → segments, and word wrap of segments into lines.
-- A segment is { text, hl, marks }: hl is nil, a group, or a list of groups
-- (merged, later wins); marks are extra { start, end, group } byte ranges.
local ts = vim.treesitter
local strwidth = vim.api.nvim_strwidth
local M = {}

local function child(node, type)
  for c in node:iter_children() do
    if c:type() == type then return c end
  end
end

-- Display width of a line of segments.
function M.width(segs)
  local w = 0
  for _, s in ipairs(segs) do
    if s[1] ~= '\n' then w = w + strwidth(s[1]) end
  end
  return w
end

local ENTITIES = {
  amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' ', copy = '©', reg = '®',
  trade = '™', mdash = '—', ndash = '–', hellip = '…', rarr = '→', larr = '←', times = '×',
}

local SUPERSCRIPT = { ['0'] = '⁰', ['1'] = '¹', ['2'] = '²', ['3'] = '³', ['4'] = '⁴', ['5'] = '⁵', ['6'] = '⁶', ['7'] = '⁷', ['8'] = '⁸', ['9'] = '⁹' }

-- Footnote label as shown: superscript digits, else [label].
function M.note(label)
  return label:match('^%d+$') and (label:gsub('%d', SUPERSCRIPT)) or '[' .. label .. ']'
end

-- Inline markdown → segments. A { '\n' } segment is a hard line break.
function M.parse(text, hl)
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
  -- `literal`: this node's delimiters are text, not markup
  local function walk(node, hls, literal)
    local pos, stop = span(node)
    -- anonymous children are punctuation ("/", ":"); they stay in the text runs
    for c in node:iter_children() do
      if not c:named() then goto continue end
      local cs, ce = span(c)
      push(text:sub(pos + 1, cs), hls)
      pos = ce
      local t = c:type()
      -- an "_" touching a letter or digit outside never opens or closes
      -- emphasis (CommonMark); tree-sitter still pairs "Question_1 … Answer_1"
      local intraword = (t == 'emphasis' or t == 'strong_emphasis') and text:sub(cs + 1, cs + 1) == '_'
        and (text:sub(cs, cs):match('%w') or text:sub(ce + 1, ce + 1):match('%w'))
      if intraword then
        walk(c, hls, true)
      elseif t == 'emphasis' then
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
        local tag = text:sub(cs + 1, ce)
        if tag:match('^<[bB][rR]') then segs[#segs + 1] = { '\n' } end
        local alt = tag:match('^<[iI][mM][gG][^>]-alt="([^"]*)"')
        if alt then segs[#segs + 1] = { '󰋩 ' .. alt, with(hls, 'VellumMuted') } end
      elseif t == 'shortcut_link' then -- "[x]" without a definition is literal text, "[^x]" a footnote
        local label = text:sub(cs + 1, ce):match('^%[%^([^%]]+)%]$')
        if label then segs[#segs + 1] = { M.note(label), with(hls, 'VellumLink') } else push(text:sub(cs + 1, ce), hls) end
      elseif not t:match('delimiter$') then
        walk(c, hls)
      elseif literal then
        push(text:sub(cs + 1, ce), hls)
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
function M.wrap(segs, width)
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

return M
