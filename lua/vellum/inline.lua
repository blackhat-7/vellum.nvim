-- Inline markdown → segments, and word wrap of segments into lines.
-- A segment is { text, hl, marks }: hl is nil, a group, or a list of groups
-- (merged, later wins); marks are extra { start, end, group } byte ranges.
-- A link's segments also carry `link`: its destination, or { ref = label }
-- for a reference link, resolved when followed so the block cache stays right.
local media = require('vellum.media')
local latex = require('vellum.latex')

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

-- Inline markdown → segments under `hl`, a group or list of groups. A
-- { '\n' } segment is a hard line break.
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
    -- Obsidian's ==highlight==, hugging its text like emphasis does
    local a, marked, b = s:match('()==([^%s=][^=]-)==()')
    if a and not marked:match('%s$') then
      push(s:sub(1, a - 1), hls)
      push(marked, with(hls, 'VellumMark'))
      return push(s:sub(b), hls)
    end
    local i = 1
    if not (vim.tbl_contains(hls, 'VellumLink') or vim.tbl_contains(hls, 'VellumCode')) then
      -- GFM autolinks bare URLs
      for a, url, b in s:gmatch('()(https?://[^%s<>]*[^%s<>%.,;:!%?%)%]\'"])()') do
        if a > i then segs[#segs + 1] = { s:sub(i, a - 1), hls } end
        segs[#segs + 1] = { url, with(hls, 'VellumLink'), link = url }
        i = b
      end
    end
    if i <= #s then segs[#segs + 1] = { s:sub(i), hls } end
  end
  -- a small image sits in the line; any other shows its alt text and keeps
  -- `image`, so wrap can put the picture on lines of its own
  local function picture(src, alt, hls)
    local seg = src and media.inline(src)
    segs[#segs + 1] = seg or { '󰋩 ' .. alt, with(hls, 'VellumMuted'), image = src }
  end
  local function span(n) return select(3, n:start()), select(3, n:end_()) end
  local function slice(n)
    local a, b = span(n)
    return text:sub(a + 1, b)
  end
  -- "$$…$$" is display math. "$…$" is math only when it hugs its content and
  -- no digit follows (Pandoc's rule), so "$5 and $10" stays text.
  local function formula(src, after, hls)
    local n = #src:match('^%$*')
    local body = src:sub(n + 1, -n - 1)
    -- a closing HTML tag means the dollars sit in different tags: "<code>$</code> … <code>$</code>"
    local ok = n <= 2 and #src > 2 * n and src:sub(-n) == ('$'):rep(n) and body:match('%S') and not body:find('</%a')
    if n == 1 then
      ok = ok and not body:match('^%s') and not body:match('%s$') and not after:match('%d')
      body = body:match('^`(.*)`$') or body -- GitHub's $`…`$ form
    end
    if not ok then -- the "$" is text; what follows may still be markdown
      push('$', hls)
      return vim.list_extend(segs, M.parse(src:sub(2), hls))
    end
    segs[#segs + 1] = { latex.text(body), with(hls, 'VellumMath'), display = n == 2 and body or nil }
  end
  -- `literal`: this node's delimiters are text, not markup
  local function walk(node, hls, literal)
    local pos, stop = span(node)
    -- anonymous children are punctuation ("/", ":"); they stay in the text runs
    for c in node:iter_children() do
      if not c:named() then goto continue end
      local cs, ce = span(c)
      -- Obsidian's [[note]] parses as "[", a "[note]" link, "]": take all three
      if c:type() == 'shortcut_link' and text:sub(cs, cs) == '[' and text:sub(ce + 1, ce + 1) == ']' then
        cs, ce = cs - 1, ce + 1
      end
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
      elseif t == 'latex_block' then
        formula(text:sub(cs + 1, ce), text:sub(ce + 1, ce + 1), hls)
      elseif t == 'inline_link' or t == 'full_reference_link' or t == 'collapsed_reference_link' then
        local label, dest, ref = child(c, 'link_text'), child(c, 'link_destination'), child(c, 'link_label')
        local link = t == 'inline_link' and (dest and slice(dest):match('^<(.*)>$') or dest and slice(dest) or '')
          or { ref = ref and slice(ref):sub(2, -2) or label and slice(label) or '' }
        local first = #segs + 1
        if label then walk(label, with(hls, 'VellumLink')) end
        for k = first, #segs do segs[k].link = link end
      elseif t == 'image' then
        local alt, dest = child(c, 'image_description'), child(c, 'link_destination')
        picture(dest and (slice(dest):match('^<(.*)>$') or slice(dest)), alt and slice(alt) or 'image', hls)
      elseif t == 'uri_autolink' or t == 'email_autolink' then
        local target = text:sub(cs + 2, ce - 1)
        segs[#segs + 1] = { target, with(hls, 'VellumLink'), link = t == 'email_autolink' and 'mailto:' .. target or target }
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
        if tag:match('^<[iI][mM][gG]') then picture(tag:match('src="([^"]*)"'), tag:match('alt="([^"]*)"') or 'image', hls) end
      elseif t == 'shortcut_link' then -- "[x]" without a definition is literal text, "[^x]" a footnote
        local raw = text:sub(cs + 1, ce)
        local label = raw:match('^%[%^([^%]]+)%]$')
        local wiki, alias = raw:match('^%[%[([^%]|]+)|?([^%]]*)%]%]$')
        if label then
          segs[#segs + 1] = { M.note(label), with(hls, 'VellumLink') }
        elseif wiki then -- Obsidian's [[note#heading|shown text]]
          segs[#segs + 1] = { alias ~= '' and alias or (wiki:gsub('#', ' › ')), with(hls, 'VellumLink'), link = { wiki = wiki } }
        else
          push(raw, hls)
        end
      elseif not t:match('delimiter$') then
        walk(c, hls)
      elseif literal then
        push(text:sub(cs + 1, ce), hls)
      end
      ::continue::
    end
    push(text:sub(pos + 1, stop), hls)
  end
  walk(ts.get_string_parser(text, 'markdown_inline'):parse()[1]:root(), type(hl) == 'table' and hl or { hl })
  return segs
end

-- Display math on lines of its own: the KaTeX picture, else its text form
-- centered, with the renderer's complaint if it has one. `key` names its place in
-- the document, so an edit shows the last picture until the new one is ready.
function M.display(tex, width, key)
  local pic, err = latex.picture(tex, width, key)
  if pic then return pic end
  local out = M.wrap({ { latex.text(tex), { 'VellumMath' } } }, width)
  for _, l in ipairs(out) do table.insert(l, 1, { string.rep(' ', math.floor((width - M.width(l)) / 2)) }) end
  return err and vim.list_extend(out, M.wrap({ { '✗ ' .. err, { 'VellumError' } } }, width)) or out
end

-- Greedy word wrap. A word may span segments ("**bold**,"), so breaks happen
-- only at whitespace; a word wider than the line is split by characters.
-- An image segment that can be shown, and display math, become lines of
-- their own. `key`: the source row, see M.display.
function M.wrap(segs, width, key)
  local lines, line, w = {}, {}, 0
  local word, ww, space = {}, 0, nil
  local function newline() lines[#lines + 1], line, w = line, {}, 0 end
  local function put(text, hl, cw, link)
    local last = line[#line]
    if last and last[2] == hl and last.link == link then
      last[1] = last[1] .. text
    else
      line[#line + 1] = { text, hl, link = link }
    end
    w = w + cw
  end
  local function flush()
    if ww == 0 then return end
    if w > 0 and w + (space and 1 or 0) + ww > width then newline() end
    if space and w > 0 then put(' ', space[1], 1, space.link) end
    for _, p in ipairs(word) do
      if ww <= width then
        put(p[1], p[2], strwidth(p[1]), p.link)
      else
        for ch in p[1]:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
          local cw = strwidth(ch)
          if w > 0 and w + cw > width then newline() end
          put(ch, p[2], cw, p.link)
        end
      end
    end
    word, ww, space = {}, 0, nil
  end
  local k = 0
  for _, s in ipairs(segs) do
    local pic = s.image and media.image(s.image, width)
    if s.display then
      k = k + 1
      pic = M.display(s.display, width, key and key .. ':' .. k)
    end
    if pic then
      flush()
      if w > 0 then newline() end
      vim.list_extend(lines, pic)
      space = nil
    elseif s[1] == '\n' then
      flush()
      newline()
      space = nil
    else
      local t, i = s[1], 1
      while i <= #t do
        local a, b = t:find('^%s+', i)
        if a then
          flush()
          space = space or { s[2] or {}, link = s.link }
        else
          a, b = t:find('^%S+', i)
          local piece = t:sub(a, b)
          word[#word + 1] = { piece, s[2], link = s.link }
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
