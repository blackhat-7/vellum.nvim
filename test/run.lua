-- Assertion tests. Run: nvim --clean -l test/run.lua
vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))

-- a private cache, filled past the 100 MB cap with sparse files of age 1..3,
-- before the plugin loads and prunes it
vim.env.XDG_CACHE_HOME = vim.fn.tempname()
local cache = vim.fn.stdpath('cache') .. '/vellum'
vim.fn.mkdir(cache, 'p')
for age = 1, 3 do
  local f = io.open(cache .. '/' .. age .. '.png', 'wb')
  f:seek('set', 60 * 1024 * 1024 - 1)
  f:write('x')
  f:close()
  vim.uv.fs_utime(cache .. '/' .. age .. '.png', os.time() - age * 60, os.time() - age * 60)
end

local render = require('vellum.render')
local image = require('vellum.image')
require('vellum.theme').apply()
image.supported = false -- diagrams render as code panels: deterministic, no browser

local failed, count = 0, 0
local function check(name, ok, detail)
  count = count + 1
  if not ok then
    failed = failed + 1
    print('FAIL ' .. name .. (detail and (': ' .. detail) or ''))
  end
end

local function doc(text, width)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n'))
  render.reset()
  local lines, rows, _, anchors = render.render(buf, width or 84, 100)
  return lines, rows, anchors, buf
end

local function find(lines, pat)
  for i, l in ipairs(lines) do
    if l:find(pat) then return i, l end
  end
end

local sample = table.concat(vim.fn.readfile('test/sample.md'), '\n')

-- no line is wider than the window, at any width (a table too wide to fit
-- scrolls sideways instead of splitting words, as on GitHub)
for _, w in ipairs({ 24, 40, 57, 80, 84, 121, 200 }) do
  local lines = doc(sample, w)
  for i, l in ipairs(lines) do
    local sw = vim.api.nvim_strwidth(l)
    if sw > w and not l:find('[│╭╰├]') then check('width ' .. w, false, ('line %d is %d wide: %s'):format(i, sw, l)) break end
  end
end

-- the cache kept only what fits in 100 MB, newest first
check('cache pruned', vim.uv.fs_stat(cache .. '/1.png') and not vim.uv.fs_stat(cache .. '/2.png') and not vim.uv.fs_stat(cache .. '/3.png'))

-- a cached re-render equals a fresh one
do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(sample, '\n'))
  render.reset()
  local a, am = render.render(buf, 84, 100)
  local b, bm = render.render(buf, 84, 100)
  render.reset()
  local c, cm = render.render(buf, 84, 100)
  check('fresh equals cached', vim.deep_equal(a, c) and vim.deep_equal(am, cm))
  check('cache lines', vim.deep_equal(a, b))
  check('cache marks', vim.deep_equal(am, bm))
end

-- anchors are ordered and point inside the output
do
  local lines, _, anchors = doc(sample)
  local ok, prev = true, { -1, 0, -1, 0 }
  for _, a in ipairs(anchors) do
    if a[1] < prev[1] or a[3] < prev[3] or a[3] + a[4] > #lines then ok = false end
    prev = a
  end
  check('anchors ordered', ok and #anchors > 10)
end

-- block structure
do
  local lines = doc(sample)
  local i = find(lines, '3%. three')
  check('blank between lists', i and lines[i - 1]:match('^%s*$'))
  check('alert title', find(lines, 'Note') and not find(lines, '%[!NOTE%]'))
  check('table border', find(lines, '╭') and find(lines, '╰'))
  check('comment hidden', not find(lines, 'hidden comment'))
  check('html text kept', find(lines, 'centered html'))
  check('escape', find(lines, 'Escaped %*star%*'))
  check('entities', find(lines, '& entity → arrow'))
  check('hard break', find(lines, '^%s*Hard break above'))
  check('setext-free doc renders all headings', find(lines, 'Level 6'))
end

-- container prefixes are stripped from nested content
do
  local lines = doc('- item\n\n  ```lua\n  x = 1\n  ```') -- width 84 → margin 2, bullet 2, panel pad 2
  check('code in list keeps no indent', find(lines, '^      x = 1'), vim.inspect(lines))
  lines = doc('> ```\n> y = 2\n> ```')
  local _, l = find(lines, 'y = 2')
  check('code in quote has no ">"', l and not l:find('>'), l)
  lines = doc('> a\n> b')
  check('quote paragraph joins lines', find(lines, 'a b'))
end

-- headings
do
  local lines = doc('Title\n=====\n\nSub\n---\n\n# Closed #')
  check('setext h1', find(lines, 'Title') and find(lines, '▔'))
  check('setext h2', find(lines, 'Sub') and find(lines, '─'))
  check('setext inside a list item', pcall(doc, '- one\n  two\n  -\n'))
  check('atx closing hashes stripped', find(lines, 'Closed') and not find(lines, 'Closed #'))
end

-- wrapping and edge cases
do
  local url = 'https://example.com/' .. string.rep('a', 150)
  local lines = doc('see ' .. url, 60)
  local ok = true
  for _, l in ipairs(lines) do ok = ok and vim.api.nvim_strwidth(l) <= 60 end
  check('long word wraps', ok)
  lines = doc('**bold**, next', 84)
  check('punctuation stays with word', find(lines, 'bold, next'))
  check('empty doc', #doc('') >= 1)
  check('unclosed fence', find(doc('```lua\nz = 3'), 'z = 3'))
  check('tabs expand', find(doc('```\n\tq\n```'), '    q'))
  lines = doc('| a | b |\n|---|---|\n| ' .. string.rep('word ', 40) .. '| x |', 50)
  ok = true
  for _, l in ipairs(lines) do ok = ok and vim.api.nvim_strwidth(l) <= 50 end
  check('wide table fits', ok)
  lines = doc('| a | b | c |\n|---|---|---|\n| Supercalifragilistic | Antidisestablishment | Floccinaucinihilipilification |', 40)
  check('wide table keeps words whole', find(lines, 'Supercalifragilistic') and find(lines, 'Floccinaucinihilipilification'), vim.inspect(lines))
  check('html img alt', find(doc('<p>\n<img alt="Big logo" src="x.png">\n</p>'), '󰋩 Big logo'))
  lines = doc('```json,title=A%20very%20long%20title&mediatype=application/vnd.x\n{}\n```', 40)
  check('long info string', find(lines, 'json') and not find(lines, 'title'), vim.inspect(lines))
  lines = doc('| a | b |\n|---|---|\n| x | 1 |\n|  |  |\n| y | 2 |\n\n```\n|  |  |\n```', 60)
  check('table survives an all-empty row', find(lines, '│ y +│ 2 │') and not find(lines, '| y'), vim.inspect(lines))
  lines = doc('| A | B | C |\n|---|---|---|\n| **Misc** |||\n| x | y | z |\n\n```\n|| keep ||\n```', 60)
  check('row with || cells', find(lines, '│ Misc │') and find(lines, '|| keep ||'), vim.inspect(lines))
  check('no zero-width space leaks', not table.concat(lines):find('\226\128\139'))
  check('inline html img alt', find(doc('<img src="nope.png" width="4"\n  alt="Sample receipt">\n\nText <img alt="icon" src="i.png"> here.'), '󰋩 Sample receipt'))
  check('inline img in text', find(doc('Text <img alt="icon" src="i.png"> here.'), 'Text 󰋩 icon here'))
  lines = doc('<details>\n<summary>More <b>info</b></summary>\n\nBody *text*\n\n</details>\n\n<details><summary>S</summary>inside</details>')
  check('details summary', find(lines, '▾ More info') and find(lines, 'Body text') and not find(lines, 'details'), vim.inspect(lines))
  check('details in one block', find(lines, '▾ S$') and find(lines, '^%s*inside$'), vim.inspect(lines))
  check('ordered start', find(doc('7. a\n8. b'), '7%. a'))
  check('task list', find(doc('- [x] done'), '󰄵 done'))
  local l, rows = doc('go to https://a.b/c. now')
  local i = find(l, 'https://a.b/c%. now')
  local m = i and rows[i] and rows[i][1]
  check('bare url is a link, minus the period', m and m[3] == 'VellumLink' and l[i]:sub(m[1] + 3, m[2] + 2) == 'https://a.b/c', vim.inspect(m))
end

-- footnotes
do
  local lines = doc('A note[^1] and [^x].\n\n[^1]: First.\n[^x]: Second one\nwraps on.')
  check('empty footnote label', pcall(doc, '[^]: x\n\n[^]: two words'))
  check('footnote refs', find(lines, 'A note¹ and %[x%]%.'), vim.inspect(lines))
  check('footnote defs', find(lines, '^  ¹ First%.$') and find(lines, '^  %[x%] Second one wraps on%.$'), vim.inspect(lines))
end

-- math: inline as Unicode text, display as its own centered lines (no
-- images here, so display math shows its text form too)
do
  local latex = require('vellum.latex')
  for tex, want in pairs({
    ['x^2 + y_i = z^{2n+1}'] = 'x² + yᵢ = z²ⁿ⁺¹',
    ['\\alpha \\leq \\beta \\neq \\infty'] = 'α ≤ β ≠ ∞',
    ['\\frac{a+b}{c} = \\frac12'] = '(a + b)/c = 1/2',
    ['\\sqrt{x^2+1} + \\sqrt[3]{8}'] = '√(x² + 1) + ∛8',
    ['\\sum_{i=1}^{n} i'] = '∑ᵢ₌₁ⁿ i',
    ['\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx'] = '∫_(−∞)^∞ e^(−x²) dx',
    ['\\lim_{x \\to 0} \\frac{\\sin x}{x}'] = 'lim_(x→0) (sin x)/x',
    ['O(n \\log n)'] = 'O(n log n)',
    ['a = -b'] = 'a = −b',
    ['\\mathbb{R}^n \\subseteq \\mathcal{L}'] = 'ℝⁿ ⊆ ℒ',
    ['\\hat{x} + \\vec{v}'] = 'x̂ + v⃗',
    ['\\text{if } x > 0'] = 'if x > 0',
    ['\\left\\{ x \\mid x \\in S \\right\\}'] = '{x ∣ x ∈ S}',
    ['\\left. f \\right|_0^1'] = 'f|₀¹',
    ['\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}'] = '(1  2; 3  4)',
    ['\\begin{aligned} a &= b \\\\ c &= d \\end{aligned}'] = 'a = b; c = d',
    ['\\not= \\not\\in'] = '≠ ∉',
    ['a \\equiv b \\pmod{n}'] = 'a ≡ b (mod n)',
    ['\\color{red} x'] = 'x',
    ['\\foo{x}'] = '\\foo x', -- unknown commands are shown, never dropped
    ['\\frac'] = '/', ['x^'] = 'x', ['{'] = '', ['}}'] = '', ['\\'] = '\\', ['\\begin{cases}'] = '{ ',
  }) do
    check('latex ' .. tex, latex.text(tex) == want, latex.text(tex))
  end
  local function has(lines, s)
    for _, l in ipairs(lines) do
      if l:find(s, 1, true) then return l end
    end
  end
  local lines = doc('Euler $e^{i\\pi} + 1 = 0$ and $`\\sqrt{2}`$ here.')
  check('inline math', has(lines, 'Euler e^(iπ) + 1 = 0 and √2 here.'), vim.inspect(lines))
  lines = doc('It costs $5 and $10, a $ x $ gap, \\$3.')
  check('dollars stay text', has(lines, 'It costs $5 and $10, a $ x $ gap, $3.'), vim.inspect(lines))
  lines = doc('Text before\n$$\n\\frac{a}{b}\\,c\n$$\nafter', 40)
  local i = find(lines, 'a/b c')
  check('display math on its own centered line', i and lines[i]:match('^%s+a/b c$') and #lines[i] > 20
    and find(lines, 'Text before$') and find(lines, '^%s*after$'), vim.inspect(lines))
  check('math fence', has(doc('```math\nx^2\n```'), 'x²'))
  check('markdown inside a non-math $ span', has(doc('Pay $5 to [site](http://x) and $10.'), 'Pay $5 to site and $10.'))
  check('dollars in separate html tags are text', has(doc('Use <code>$\\`</code> and <code>\\`$</code> here.'), 'Use $` and `$ here.'),
    vim.inspect(doc('Use <code>$\\`</code> and <code>\\`$</code> here.')))
  check('nested scripts stay nested', latex.text('a^{b^{c}}') == 'a^(bᶜ)', latex.text('a^{b^{c}}'))
  check('NUL in a script', pcall(doc, 'a $x^{a\0b}$ c'))
  check('deep nesting shows the source', latex.text(('{'):rep(10000)) == ('{'):rep(10000))
  check('math in a table cell stays in the cell', find(doc('| a |\n|---|\n| $$x^2$$ |'), '│ x² │'))
end

-- inline styles land on the right text: the group covering `word`'s first byte
do
  local function style(text, word)
    local l, rows = doc(text)
    for i, line in ipairs(l) do
      local at = line:find(word, 1, true)
      if at then
        local groups = {}
        for _, m in ipairs(rows[i] or {}) do
          if m[1] + 2 < at and at <= m[2] + 2 then groups[#groups + 1] = m[3] end
        end
        return table.concat(groups, ' ')
      end
    end
    return 'not found'
  end
  local md = 'a **bold** b *ital* c ~~gone~~ d `mono` e [label](http://x) f'
  check('bold', style(md, 'bold'):find('Bold'), style(md, 'bold'))
  check('italic', style(md, 'ital'):find('Italic'), style(md, 'ital'))
  check('strike', style(md, 'gone'):find('Strike'), style(md, 'gone'))
  check('code', style(md, 'mono'):find('Code'), style(md, 'mono'))
  check('link', style(md, 'label'):find('Link'), style(md, 'label'))
  check('plain', style(md, ' f') == '', style(md, ' f'))
  check('nested', style('***both***', 'both'):find('Bold') and style('***both***', 'both'):find('Italic'), style('***both***', 'both'))
  check('heading color', style('## Head', 'Head'):find('H2'), style('## Head', 'Head'))
  check('syntax', style('```lua\nlocal v = 1\n```', 'local'):find('@keyword'), style('```lua\nlocal v = 1\n```', 'local'))
  check('table head', style('| h |\n|---|\n| c |', 'h'):find('TableHead'), style('| h |\n|---|\n| c |', 'h'))
  check('html block keeps a bare <', find(doc('<recap>\nRecap: <40 words, 1-2 sentences.\n</recap>'), 'Recap: <40 words, 1%-2 sentences%.'))
  check('intraword underscores are literal', find(doc('Question_1: hello\nResponse_1: world'), 'Question_1: hello Response_1: world'))
  check('real underscore emphasis', style('an _ital_ word', 'ital'):find('Italic'), style('an _ital_ word', 'ital'))
  check('alert color', style('> [!TIP]\n> x', 'Tip'):find('Tip'), style('> [!TIP]\n> x', 'Tip'))
end

-- fuzz: random edits of the sample never crash and never overflow the window
do
  math.randomseed(42)
  local pieces = { '\n', ' ', '*', '_', '`', '```', '> ', '- ', '1. ', '|', '#', '[', ']', '(', ')', '!', '<', '>', '\\', '~~', '[!NOTE]', '[^1]', '\n[^a]: ', '---', '\t', 'é', '漢', '    ', '$', '$$', '\\frac{', '^{', '\\begin{pmatrix}', '\\left(', '\\end{x}', '```math\n' }
  local crashes, overflow = 0, 0
  for _ = 1, 300 do
    local text = sample
    for _ = 1, math.random(1, 8) do
      local at = math.random(0, #text)
      if math.random() < 0.3 then
        text = text:sub(1, at) .. text:sub(at + math.random(1, 20))
      else
        text = text:sub(1, at) .. pieces[math.random(#pieces)] .. text:sub(at + 1)
      end
    end
    local w = math.random(22, 160)
    local ok, lines = pcall(doc, text, w)
    if not ok then
      crashes = crashes + 1
      if crashes == 1 then print(lines) end
    else
      for _, l in ipairs(lines) do
        if vim.api.nvim_strwidth(l) > w and not l:find('[│╭╰├]') then -- a table may be too wide to fit
          overflow = overflow + 1
          if overflow == 1 then print(('overflow at %d: %s'):format(w, l)) end
          break
        end
      end
    end
  end
  check('fuzz: no crash', crashes == 0, crashes .. ' crashes')
  check('fuzz: no overflow', overflow == 0, overflow .. ' docs')
end

-- the preview window: open, live edit, follow buffers, close, reopen
do
  local vellum = require('vellum')
  vim.cmd('enew')
  vim.bo.filetype = 'markdown'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# One' })
  local src = vim.api.nvim_get_current_buf()
  vellum.open()
  local wins = #vim.api.nvim_tabpage_list_wins(0)
  local pbuf = vim.fn.bufnr('vellum://preview')
  local function shown(pat) return find(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), pat) end
  check('opens a split', wins == 2 and pbuf > 0)
  check('focus stays in source', vim.api.nvim_get_current_buf() == src)
  check('first draw', shown('One'))
  vim.api.nvim_buf_set_lines(src, 0, -1, false, { '# Two' })
  vellum.redraw()
  check('redraws edits', shown('Two') and not shown('One'))
  vim.cmd('enew')
  vim.bo.filetype = 'markdown'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'Three' })
  vim.api.nvim_exec_autocmds('BufEnter', { buffer = 0 })
  vellum.redraw()
  check('follows the markdown buffer', shown('Three'))
  vellum.toggle()
  check('toggle closes', #vim.api.nvim_tabpage_list_wins(0) == 1 and vim.fn.bufnr('vellum://preview') == -1)
  vellum.toggle()
  pbuf = vim.fn.bufnr('vellum://preview')
  check('toggle reopens', #vim.api.nvim_tabpage_list_wins(0) == 2 and shown('Three'))
  vim.api.nvim_win_close(vim.fn.bufwinid(pbuf), true)
  vim.wait(50)
  vellum.toggle()
  check('reopens after :close', #vim.api.nvim_tabpage_list_wins(0) == 2)
  pbuf = vim.fn.bufnr('vellum://preview')
  vim.cmd('enew')
  vim.bo.filetype = 'markdown.mdx' -- MDX as some configs set it up
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'Four' })
  vim.api.nvim_exec_autocmds('BufEnter', { buffer = 0 })
  vellum.redraw()
  check('follows an mdx buffer', shown('Four'))
  -- Neovim gives .mdx no filetype; the name is enough
  vim.cmd('enew')
  vim.api.nvim_buf_set_name(0, vim.fn.tempname() .. '.mdx')
  check('plain nvim gives .mdx no filetype', vim.bo.filetype == '', vim.bo.filetype)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'Five' })
  vim.api.nvim_exec_autocmds('BufEnter', { buffer = 0 })
  vellum.redraw()
  check('follows an .mdx file with no filetype', shown('Five'))
  vellum.close()
end

-- MDX: import/export statements and {/* comments */} are hidden, in place;
-- the same words in code, quotes or prose, and in a .md file, stay
do
  local text = table.concat({
    'import { Chart } from "./chart"',
    'export const meta = {',
    '  title: "x",',
    '}',
    '',
    '# Title',
    '',
    '{/* a hidden note */}',
    '',
    'Words like import stay in prose.',
    '',
    '```js',
    'import x from "y"',
    '```',
    '',
    '> export in a quote stays',
    '',
    '## Sub',
    '',
    'export default Layout',
  }, '\n')
  local function shows(name)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. name)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n'))
    render.reset()
    local lines, _, _, anchors = render.render(buf, 84, 100)
    return function(pat) return find(lines, pat) ~= nil end, anchors
  end
  local has, anchors = shows('.mdx')
  check('mdx import hidden', not has('Chart'))
  check('mdx multi-line export hidden', not has('meta') and not has('title'))
  check('mdx export in a section hidden', not has('Layout'))
  check('mdx comment hidden', not has('hidden note'))
  check('mdx keeps headings and prose', has('Title') and has('Sub') and has('like import stay'))
  check('mdx keeps code', has('import x from'))
  check('mdx keeps quotes', has('export in a quote'))
  check('mdx rows stay put', anchors[1] and anchors[1][1] == 5, vim.inspect(anchors[1]))
  has = shows('.md')
  check('markdown shows the same text', has('Chart') and has('hidden note'))
  -- hiding is part of the block cache key: an .md after an .mdx still shows
  -- what the .mdx hid, top-level and inside a cached heading section
  local function named(name, lines)
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(b, vim.fn.tempname() .. name)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    return b
  end
  local plain = { 'import { Chart } from "./chart"', '', '# Title', '', 'para', '', '## Sub', '', 'export default Layout' }
  render.render(named('.mdx', plain), 84, 100)
  local md_lines = render.render(named('.md', plain), 84, 100)
  check('mdx hiding is not cached into markdown', find(md_lines, 'Chart') ~= nil and find(md_lines, 'Layout') ~= nil)
  local buf = named('.mdx', vim.split(text, '\n'))
  local out = require('vellum.mdx').lines(buf)
  check('mdx export blanks statements and comments in place', #out == 20 and out[1] == '' and out[4] == ''
    and out[8] == '' and out[20] == '' and out[6] == '# Title' and out[13] == 'import x from "y"', vim.inspect(out))
end

-- PNG files for image checks; only their headers are read
local function u32(n) return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) end
local function phys(ppm, unit) return u32(9) .. 'pHYs' .. u32(ppm) .. u32(ppm) .. string.char(unit or 1) .. u32(0) end
local function write_png(path, w, h, chunk) -- CRCs are zero: only the headers are read
  local f = io.open(path, 'wb')
  f:write('\137PNG\r\n\26\n' .. u32(13) .. 'IHDR' .. u32(w) .. u32(h) .. string.rep('\0', 5) .. u32(0) .. (chunk or '') .. u32(0) .. 'IEND' .. u32(0))
  f:close()
  return path
end

-- images: a small one stays centered at natural size, a very wide one
-- shrinks to the width (overflowing, it showed only its empty left edge)
do
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local function png(name, w, h) write_png(dir .. '/' .. name, w, h) end
  png('wide.png', 9000, 600)
  png('small.png', 200, 100)
  png('badge.png', 80, 20)
  image.supported, vim.o.termguicolors = true, true
  local cw, ch = image.cell()
  local lines = doc('![w](' .. dir .. '/wide.png)\n\n![s](' .. dir .. '/small.png)', 84)
  local badges = doc('CI [![ci](' .. dir .. '/badge.png)](x) <img src="' .. dir .. '/badge.png"> ok\n\nsee ![s](' .. dir .. '/small.png) below', 84)
  image.supported = false
  local widest, small = 0, nil
  for _, l in ipairs(lines) do
    widest = math.max(widest, vim.api.nvim_strwidth(l))
    if l:find(vim.fn.nr2char(0x10EEEE)) then small = l end -- the last image is the small one
  end
  check('wide image fits the width', widest <= 84, widest)
  check('small image natural size', small and vim.api.nvim_strwidth(vim.trim(small)) == math.ceil(200 * ch / 24 / cw), small)
  local ph = vim.fn.nr2char(0x10EEEE)
  local _, row = find(badges, '^%s*CI ')
  local cells = math.floor(80 / 20 * ch / cw + 0.5)
  check('badges sit in the text line', row and row:find('ok$') and select(2, row:gsub(ph, '')) == 2 * cells, row)
  local i = find(badges, '^%s*see$')
  check('big image in text gets its own lines', i and badges[i + 1]:find(ph) and find(badges, '^%s*below$'), vim.inspect(badges))
  -- the preview frees images it no longer shows (old versions of an edited
  -- diagram filled kitty's image memory), never the zoom viewer's
  local drop, dropped = image.drop, {}
  image.drop = function(id) dropped[id] = true end
  image.supported = true
  local function shown_by(text)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n'))
    return select(5, render.render(buf, 84, 100))
  end
  local wide, small_id = image.id(dir .. '/wide.png'), image.id(dir .. '/small.png')
  local both = shown_by('![w](' .. dir .. '/wide.png)\n\n![s](' .. dir .. '/small.png)')
  check('render reports the images it shows', both[wide] and both[small_id], vim.inspect(both))
  local zoom_id = image.id(dir .. '/wide.png#zoom')
  image.grid(zoom_id, dir .. '/wide.png', 4, 2, 0, 0, 2, 4)
  image.keep(shown_by('![s](' .. dir .. '/small.png)'))
  check('an image no longer shown is freed; shown and zoom ones stay', dropped[wide] and not dropped[small_id] and not dropped[zoom_id], vim.inspect(dropped))
  -- images are sent when first drawn, within a budget: drawing a third
  -- 64 MB image frees the least recently drawn one that is off screen
  dropped = {}
  local big = {}
  for i = 1, 3 do
    big[i] = image.id(write_png(dir .. '/big' .. i .. '.png', 4000, 4000))
    image.lines(dir .. '/big' .. i .. '.png', 10, 10)
  end
  for i = 1, 3 do
    image.next_frame()
    image.show(big[i])
  end
  check('over budget, the least recently drawn image is freed', dropped[big[1]] and not dropped[big[2]] and not dropped[big[3]], vim.inspect(dropped))
  image.drop, image.supported = drop, false
end

-- images need 'termguicolors', read when used: Neovim may set it after startup
do
  vim.o.termguicolors = false
  check('no termguicolors, no images', (image.problem() or ''):find('termguicolors'))
  vim.o.termguicolors = true
  check('termguicolors on', image.problem() == nil or image.problem():find('tmux'))
end

-- image placeholders are exactly cols wide
do
  local lines = image.lines('/nonexistent.png', 7, 3)
  check('placeholder rows', #lines == 3)
  check('placeholder cols', vim.api.nvim_strwidth(lines[2][1][1]) == 7)
end

-- a rendered PNG's density (pixels per CSS px) comes from the pHYs chunk the
-- renderer writes right after IHDR, in pixels per metre at 96 CSS px per inch
do
  local function density(chunk) return select(3, image.png_size(write_png(vim.fn.tempname(), 10, 10, chunk))) end
  check('2x density from pHYs', density(phys(7559)) == 2, density(phys(7559)))
  check('capped density from pHYs', density(phys(4762)) == 1.26, density(phys(4762)))
  check('no pHYs, no density', density(nil) == nil)
  check('pHYs without a unit is no density', density(phys(7559, 0)) == nil)
end

-- a capped diagram is cached apart from the 2x one and keeps its size in the
-- preview: half the pixels at density 1 draw as wide as the 2x PNG
do
  local browser = require('vellum.browser')
  local theme = require('vellum.theme')
  local cache = vim.fn.stdpath('cache') .. '/vellum'
  local code = 'graph TD\n  capped --> diagram'
  local function cached(key, w, h, chunk) write_png(cache .. '/' .. vim.fn.sha256(key):sub(1, 32) .. '.png', w, h, chunk) end
  cached(theme.signature .. code, 2400, 800) -- no pHYs: rendered before the renderer wrote one
  browser.max_pixels = 1e6
  cached(theme.signature .. code .. '\0max' .. browser.max_pixels, 1200, 400, phys(3780))
  local _, capped_file, capped = browser.diagram(code, theme)
  browser.max_pixels = nil
  local _, full_file, full = browser.diagram(code, theme)
  check('uncapped diagram is the 2x PNG', full and full[1] == 2400 and full[3] == 2, vim.inspect(full))
  check('capped diagram is its own PNG', capped and capped[1] == 1200 and capped[3] == 1, vim.inspect(capped))
  local function cols(lines) return select(2, lines[1][2][1]:gsub(vim.fn.nr2char(0x10EEEE), '')) end
  local media = require('vellum.media')
  local wide, narrow = media.picture(full_file, full[1], full[2], 300, full[3]), media.picture(capped_file, capped[1], capped[2], 300, capped[3])
  check('capped diagram keeps its width', cols(wide) == cols(narrow), cols(wide) .. ' vs ' .. cols(narrow))
end

-- render loaders: none while a render is fast; then a spinner label over a new
-- diagram's code, or a badge over an edited diagram's old picture
do
  local browser, code = require('vellum.browser'), require('vellum.code')
  local diagram, supported, tgc = browser.diagram, image.supported, vim.o.termguicolors
  image.supported, vim.o.termguicolors = true, true
  code.reset()
  -- a fast render shows no loader, and the preview is told when one is due
  browser.diagram = function() return 'pending', 100 end
  local quick = code.diagram('graph LR; A --> B', 40, 99, 'mermaid')
  local due_in = code.due and code.due - vim.uv.now()
  check('fast new diagram has no spinner', quick[1][2][2] == 'VellumCodeLabel' and due_in and due_in > 250 and due_in <= 300 and not code.loading,
    vim.inspect(quick[1]) .. ' ' .. tostring(due_in))
  code.due = nil
  browser.diagram = function() return 'pending', 5000 end
  local out = code.diagram('graph LR; A --> B', 40, 99, 'mermaid')
  local head = out[1]
  local text = table.concat(vim.tbl_map(function(s) return s[1] end, head))
  check('pending diagram has a spinner label', head[2][1] == '⠋ rendering…' and head[2][2] == 'VellumSpinner' and code.loading, vim.inspect(head))
  code.loading = false
  check('spinner label fits the panel', vim.api.nvim_strwidth(text) == 40, text)
  check('pending diagram shows its code', out[2][2][1] == 'graph LR; A --> B')

  -- an edit keeps the old picture, with a badge over the last 12 cells of its top row
  local file = vim.fn.tempname() .. '.png'
  write_png(file, 400, 100)
  browser.diagram = function() return 'ready', file, { 400, 100, 1 } end
  local ready = code.diagram('graph LR; A --> B', 40, 99, 'mermaid')
  browser.diagram = function() return 'pending', 200 end
  check('fast edit keeps the picture without a badge', code.diagram('graph LR; A --> C', 40, 99, 'mermaid') == ready and code.due and not code.loading)
  code.due = nil
  browser.diagram = function() return 'pending', 5000 end
  local updating = code.diagram('graph LR; A --> C', 40, 99, 'mermaid')
  browser.diagram, image.supported, vim.o.termguicolors = diagram, supported, tgc
  local top, ph = updating[1], image.placeholder
  check('updating picture keeps its rows', #updating == #ready and updating[2] == ready[2])
  check('updating badge replaces trailing cells only', top[3] and top[3][2] == 'VellumBadge' and top[3][1] == ' ⠋ updating '
    and top[2][1] .. ph:rep(12) == ready[1][2][1], vim.inspect(top[3]))
  check('ready picture has no badge', #ready[1] == 2)
end

-- D2: fenced like mermaid; shown as code without image support, else a
-- picture keyed by theme, folder, local icon versions and code
do
  local lines = doc('```d2\nserver -> db: query\n```')
  check('d2 without images shows its code', find(lines, 'server %-> db: query') ~= nil)
  local browser = require('vellum.browser')
  local theme = require('vellum.theme')
  local cache = vim.fn.stdpath('cache') .. '/vellum'
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. '/icons', 'p')
  vim.fn.writefile({ '<svg/>' }, dir .. '/icons/a b.svg')
  local code = 'a: { icon: "./icons/a b.svg" }\nb.icon: https://example.com/b.svg\na -> b'
  local function key()
    local s = vim.uv.fs_stat(dir .. '/icons/a b.svg')
    local d2 = browser.d2_command()
    local by = d2 and d2.bin .. ' ' .. d2.version or 'bundled'
    return table.concat({ 'd2', by, theme.d2_signature, dir, './icons/a b.svg\0' .. s.mtime.sec .. '.' .. s.size, code }, '\0')
  end
  local function cached(k) return write_png(cache .. '/' .. vim.fn.sha256(k):sub(1, 32) .. '.png', 300, 100, phys(7559)) end
  local first = cached(key())
  local state, file = browser.diagram(code, theme, 'd2', dir)
  check('d2 diagram is found by its key, a URL icon not read as a file', state == 'ready' and file == first, vim.inspect({ state, file }))
  vim.fn.writefile({ '<svg></svg>' }, dir .. '/icons/a b.svg') -- one byte more
  local second = cached(key())
  state, file = browser.diagram(code, theme, 'd2', dir)
  check('an edited local icon is a new d2 picture', state == 'ready' and file == second and second ~= first, vim.inspect({ state, file }))
  check('the d2 theme follows the lightness of the colorscheme',
    theme.d2.themeID == (vim.o.background == 'dark' and 200 or 0) and theme.d2.themeOverrides.N7 == theme.mermaid.background)
end

-- Obsidian: callouts, ==highlight==, [[wikilinks]]
do
  local lines = doc('> [!question]- Why *here*?\n> body line')
  check('callout title from its line', find(lines, '󰅾  Why here%?') and find(lines, 'body line') and not find(lines, '%[!'), vim.inspect(lines))
  lines = doc('> [!tip]\n> text')
  check('callout without title uses its type', find(lines, '󰌶  Tip') and find(lines, 'text'), vim.inspect(lines))
  lines = doc('> [!NOTE]\n> first\n> second')
  check('GitHub alert unchanged', find(lines, '󰋽  Note') and find(lines, 'first second'), vim.inspect(lines))
  lines = doc('> [!weird] x')
  check('unknown callout stays a quote', find(lines, '%[!weird%] x'), vim.inspect(lines))
  local l, rows = doc('a ==mark it== b, a == b == c')
  local i = find(l, 'a mark it b, a == b == c')
  local marked = false
  for _, m in ipairs(i and rows[i] or {}) do marked = marked or m[3] == 'VellumMark' end
  check('==highlight==', i and marked, vim.inspect(l))
  lines = doc('see [[Page#Part|alias]] and [[Other#Deep bit]] and [[Plain]]')
  check('wikilinks show their text', find(lines, 'see alias and Other › Deep bit and Plain'), vim.inspect(lines))
end

-- links keep their destination through wrapping, tables and headings, and
-- following one from the preview opens the URL, jumps, or opens the file
do
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  -- long, so the preview has to scroll to reach the heading
  local other = { '# Other', '' }
  for k = 1, 150 do other[#other + 1] = 'filler ' .. k end
  vim.list_extend(other, { '', '## Deep part', '', 'here' })
  vim.fn.writefile(other, dir .. '/other file.md')
  vim.fn.writefile({ '# Done' }, dir .. '/100%25 done.md')
  vim.fn.mkdir(dir .. '/.obsidian', 'p') -- a vault: wikilinks may search its folders
  vim.fn.mkdir(dir .. '/sub', 'p')
  vim.fn.writefile({ '# Deeper note' }, dir .. '/sub/deeper.md')
  vim.fn.writefile({
    '# Top',
    '',
    'See [the web](https://example.com/a) and [a ref][r] and <https://auto.example>.',
    '',
    '| col |',
    '| --- |',
    '| [cell](#setup) |',
    '',
    '[far](other%20file.md#deep-part) [gone](missing.md) [dup](#setup-1) [[deeper]] [[nowhere]] [[other file#Deep part|wiki]] [[100%25 done]] [snake](#snake_case-option) [dash](#école--vu) [mdx page](page.mdx)',
    '',
    '## Setup',
    '',
    '## Setup',
    '',
    '## snake_case option',
    '',
    '## École — vu',
    '',
    '[r]: https://example.com/ref',
  }, dir .. '/main.md')
  vim.fn.writefile({ '# Page' }, dir .. '/page.mdx')
  local opened
  local ui_open = vim.ui.open
  vim.ui.open = function(t) opened = t end
  local vellum = require('vellum')
  vim.cmd('silent! only | enew! | silent! %bwipeout!')
  vim.cmd.edit(dir .. '/main.md')
  vellum.open()
  local src = vim.api.nvim_get_current_win()
  local pwin = vim.fn.bufwinid('vellum://preview')
  local function click(label)
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(pwin), 0, -1, false)
    for i, l in ipairs(lines) do
      local col = l:find(label, 1, true)
      if col then
        vim.api.nvim_win_set_cursor(pwin, { i, col - 1 })
        return vellum.follow()
      end
    end
  end
  check('link opens its URL', click('the web') and opened == 'https://example.com/a', opened)
  check('reference link opens its definition', click('a ref') and opened == 'https://example.com/ref', opened)
  check('autolink opens', click('auto.example') and opened == 'https://auto.example', opened)
  check('link in a table cell jumps to the heading', click('cell') and vim.api.nvim_win_get_cursor(src)[1] == 11)
  check('second heading with the same name is -1', click('dup') and vim.api.nvim_win_get_cursor(src)[1] == 13)
  check('plain text is no link', not click('Setup'))
  check('missing file is a message, not a jump', click('gone') and vim.api.nvim_buf_get_name(0):match('main%.md$'))
  check('unknown wikilink is a message', click('nowhere') and vim.api.nvim_buf_get_name(0):match('main%.md$'))
  check('wikilink finds a note in a subfolder', click('deeper') and vim.api.nvim_buf_get_name(0):match('sub/deeper%.md$'))
  vim.cmd.edit(dir .. '/main.md')
  vim.wait(50)
  check('wikilink opens the note at its heading', click('wiki') and vim.api.nvim_buf_get_name(0):match('other file%.md$')
    and vim.api.nvim_win_get_cursor(src)[1] == #other - 2)
  vim.cmd.edit(dir .. '/main.md')
  vim.wait(50)
  check('wikilink name is a file name, not a URL', click('100%25 done') and vim.api.nvim_buf_get_name(0):match('100%%25 done%.md$'))
  vim.cmd.edit(dir .. '/main.md')
  vim.wait(50)
  check('anchor keeps underscores', click('snake') and vim.api.nvim_get_current_line() == '## snake_case option')
  check('anchor: letters kept, a dash dropped, as GitHub', click('dash') and vim.api.nvim_get_current_line() == '## École — vu')
  vim.cmd.edit(dir .. '/main.md')
  vim.wait(50)
  check('mdx file opens in the editor', click('mdx page') and vim.api.nvim_buf_get_name(0):match('page%.mdx$'), opened)
  vim.cmd.edit(dir .. '/main.md')
  vim.wait(50)
  check('relative markdown file opens at its heading', click('far') and vim.api.nvim_buf_get_name(0):match('other file%.md$')
    and vim.api.nvim_win_get_cursor(src)[1] == #other - 2)
  local plines = vim.api.nvim_buf_get_lines(vim.fn.winbufnr(pwin), 0, -1, false)
  local at = find(plines, 'Deep part')
  check('the preview shows the opened file at the heading', at and vim.fn.line('w0', pwin) <= at and at <= vim.fn.line('w$', pwin),
    at and ('heading at %d, view %d-%d'):format(at, vim.fn.line('w0', pwin), vim.fn.line('w$', pwin)))
  -- outside a vault only the note's own folder is looked in
  local loose = vim.fn.tempname()
  vim.fn.mkdir(loose .. '/sub', 'p')
  vim.fn.writefile({ '# Deeper' }, loose .. '/sub/deeper.md')
  vim.fn.writefile({ '[[deeper]]' }, loose .. '/main.md')
  vim.cmd.edit(loose .. '/main.md')
  vim.wait(50)
  check('no vault, no folder search', click('deeper') and vim.api.nvim_buf_get_name(0):match('main%.md$'))
  vim.ui.open = ui_open
  -- a link wrapped over two lines keeps its target on both
  local wrapped = require('vellum.inline').wrap(require('vellum.inline').parse('[one two three four](x.md)'), 9)
  local all = #wrapped > 1
  for _, l in ipairs(wrapped) do all = all and l[1].link == 'x.md' end
  check('wrapped link keeps its target on every line', all, vim.inspect(wrapped))
end

-- export refuses what it cannot do, with a message (the rendering itself needs Chrome)
do
  local said
  local notify = vim.notify
  vim.notify = function(m) said = m end
  vim.cmd('silent! only | enew! | silent! %bwipeout!')
  vim.cmd('edit build.lua')
  require('vellum').export()
  check('export needs markdown', said and said:find('markdown buffer'), said)
  vim.cmd('edit docs/demo.md')
  said = nil
  require('vellum').export('out.docx')
  check('export needs .pdf or .html', said and said:find('%.pdf or %.html'), said)
  said = nil
  vim.cmd('enew')
  vim.bo.filetype = 'markdown.mdx'
  require('vellum').export('out.docx')
  check('export takes mdx', said and said:find('%.pdf or %.html'), said)
  said = nil
  vim.cmd('runtime plugin/vellum.lua') -- nvim -l loads no plugin files
  vim.cmd('Vellum nonsense')
  check('unknown subcommand', said and said:find('unknown command'), said)
  -- build is wired to the renderer build; stubbed, so no terminal opens here
  local ran = false
  package.loaded['vellum.build'] = { run = function() ran = true end }
  vim.cmd('Vellum build')
  check(':Vellum build runs the renderer build', ran, said)
  package.loaded['vellum.build'] = nil
  local build = dofile('lua/vellum/build.lua')
  check('renderer build installs deps then the headless shell',
    build.commands[1][1] == 'npm' and build.commands[2][1] == 'npx'
      and vim.uv.fs_stat(build.root .. '/render/package.json') ~= nil, vim.inspect({ build.root, build.commands }))
  -- a root with % and # in it: :terminal {cmd} would have expanded them
  local root = vim.fn.tempname() .. '/a%b#c'
  vim.fn.mkdir(root .. '/render', 'p')
  build.root = root
  local jobstart, argv, opts = vim.fn.jobstart, nil, nil
  vim.fn.jobstart = function(a, o) argv, opts = a, o; return 1 end
  local wins = #vim.api.nvim_list_wins()
  build.run()
  check(':Vellum build runs both steps in render/, in a new window',
    argv and argv[1] == 'sh' and argv[3] == 'npm ci && npx puppeteer browsers install chrome-headless-shell'
      and opts.term and opts.cwd == root .. '/render' and #vim.api.nvim_list_wins() == wins + 1, vim.inspect({ argv, opts }))
  vim.cmd('close')
  -- a renderer built by a package manager (Nix) is read-only
  vim.uv.fs_chmod(root .. '/render', tonumber('555', 8))
  said, argv = nil, nil
  build.run()
  check(':Vellum build refuses a read-only renderer', said and said:find('read%-only') and argv == nil, said)
  vim.uv.fs_chmod(root .. '/render', tonumber('755', 8))
  vim.fn.jobstart = jobstart
  vim.notify = notify
end

-- the preview closes with its source, and follows a markdown buffer that replaces it
do
  local vellum = require('vellum')
  local function open()
    vim.cmd('silent! only | enew! | silent! %bwipeout!')
    vim.cmd('edit docs/demo.md')
    vellum.open()
  end
  local function after(name, action, want)
    action()
    vim.wait(20)
    check(name, (vim.fn.bufwinid('vellum://preview') ~= -1) == want)
  end
  open()
  vim.cmd('vsplit README.md')
  after('source window closed', function() vim.cmd('wincmd l') vim.cmd('quit') end, false)
  open()
  after('source unloaded', function() vim.cmd('bdelete') end, false)
  open()
  after('other markdown in the source window', function() vim.cmd('edit test/sample.md') end, true)
  open()
  after('non-markdown in the source window', function() vim.cmd('edit build.lua') end, false)
  open()
  vim.o.hidden = false
  vim.cmd('topleft split README.md | wincmd j')
  after('source unloaded by :q, hidden off', function() vim.cmd('quit') end, false)
  vim.o.hidden = true
end

-- the preview in its own tab: the source keeps its own tab, the preview tab
-- takes the focus, the tab holds nothing else, and it closes with the preview
do
  local vellum = require('vellum')
  vellum.setup({ tab = true })
  vim.cmd('silent! only | enew! | silent! %bwipeout!')
  vim.cmd('enew')
  vim.bo.filetype = 'markdown'
  local src_lines = { '# Tabbed' }
  for i = 2, 60 do
    -- blank lines between them: without them every paragraph folds into one block,
    -- the preview fits one screen, and a scrolled topline cannot be observed
    src_lines[#src_lines + 1] = ''
    src_lines[#src_lines + 1] = 'para ' .. i
  end
  vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, -1, false, src_lines)
  local src, tab = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage()
  vim.api.nvim_win_set_cursor(src, { #src_lines - 5, 0 })
  local tabs = #vim.api.nvim_list_tabpages()
  vellum.open()
  local pages = vim.api.nvim_list_tabpages()
  local last = pages[#pages] -- tabnew inserts after the current tab page: the preview tab page is the last one
  local pwin = vim.api.nvim_tabpage_list_wins(last)[1]
  local pb = vim.api.nvim_win_get_buf(pwin)
  check('opens its own tab', #pages == tabs + 1 and #vim.api.nvim_tabpage_list_wins(last) == 1
    and pb == vim.fn.bufnr('vellum://preview'), vim.inspect(pages))
  check('the preview tab takes the focus', vim.api.nvim_get_current_win() == pwin
    and vim.api.nvim_get_current_tabpage() == last and #vim.api.nvim_tabpage_list_wins(tab) == 1)
  check('the preview fills the tab, not a split', vim.api.nvim_win_get_width(pwin) == vim.o.columns,
    ('%d of %d columns'):format(vim.api.nvim_win_get_width(pwin), vim.o.columns))
  check('draws there', find(vim.api.nvim_buf_get_lines(pb, 0, -1, false), 'Tabbed'))
  -- the first draw runs with the source as the window it syncs, though the focus is this tab
  check('open starts the preview where the source cursor is',
    vim.api.nvim_win_call(pwin, vim.fn.winsaveview).topline > 1)
  vim.api.nvim_set_current_win(src)
  vim.api.nvim_win_set_cursor(src, { #src_lines - 5, 0 })
  vellum.redraw() -- draw ends with sync: the preview must follow a cursor deep in the source
  local top = vim.api.nvim_win_call(pwin, vim.fn.winsaveview).topline
  check('the preview follows the source cursor across tab pages', top > 10, tostring(top))
  vim.api.nvim_set_current_win(pwin)
  local tab_maps = { vim.fn.maparg('<Tab>', 'n', false, true).rhs, vim.fn.maparg('gt', 'n', false, true).rhs,
    vim.fn.maparg('<S-Tab>', 'n', false, true).rhs }
  vim.api.nvim_set_current_win(src)
  tab_maps[#tab_maps + 1] = vim.fn.maparg('<Tab>', 'n', false, true).rhs
  check('Tab, gt and S-Tab move tab pages in the plugin windows',
    tab_maps[1]:lower() == '<cmd>tabnext<cr>' and tab_maps[2]:lower() == tab_maps[1]:lower()
    and tab_maps[3]:lower() == '<cmd>tabprevious<cr>' and tab_maps[4]:lower() == tab_maps[1]:lower(),
    vim.inspect(tab_maps)) -- typed keys never run in this headless harness; the mapping is the plugin's contract
  vim.cmd(pb .. 'bwipeout!') -- a forced wipeout is the one way past winfixbuf: the preview goes with its buffer
  vim.wait(50)
  check('preview closes when its buffer is wiped out', vim.fn.bufnr('vellum://preview') == -1
    and #vim.api.nvim_list_tabpages() == tabs, vim.inspect(vim.api.nvim_list_tabpages()))
  vellum.close()
  check('close takes the preview tab with it', #vim.api.nvim_list_tabpages() == tabs and vim.fn.bufnr('vellum://preview') == -1)
  check('close returns the Tab keys to the source buffer', vim.fn.maparg('<Tab>', 'n') == '',
    vim.inspect(vim.fn.maparg('<Tab>', 'n', false, true)))
  -- a tab page with no source window left has nothing to preview
  vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(src), 0, -1, false, { '# Tabbed' })
  vellum.open()
  vim.cmd('tabnew | enew') -- so closing the source tab page is not closing the last one
  vim.api.nvim_set_current_win(src)
  vim.cmd('tabclose!') -- the source buffer is modified, so only a discarding close gets there
  vim.wait(50)
  check('the preview closes with its source tab', vim.fn.bufnr('vellum://preview') == -1
    and #vim.api.nvim_list_tabpages() == tabs, vim.inspect(vim.api.nvim_list_tabpages()))
  vellum.setup({ tab = false })
end

-- setup: bad options are skipped with a warning; split and size place the
-- preview; auto_open opens it on markdown in a file window; users' own
-- Vellum* colors win over the derived ones
do
  local vellum = require('vellum')
  local notify, said = vim.notify, nil
  vim.notify = function(m) said = m end
  vellum.setup({ max_widht = 80, tab = 'yes', split = 'top', size = 0.5, max_width = 90 })
  check('setup names every bad option', said and said:find('max_widht') and said:find('tab should be a boolean')
    and said:find('split should be') and said:find('size should be'), said)
  check('setup keeps good options and defaults for bad ones', vellum.config.max_width == 90 and vellum.config.tab == false
    and vellum.config.split == 'right' and vellum.config.size == nil, vim.inspect(vellum.config))
  said = nil
  vellum.setup({ max_width = 100 })
  check('good options say nothing', said == nil, said)
  vim.notify = notify

  vim.cmd('silent! only | enew!')
  local src = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# Split' })
  vim.bo.filetype = 'markdown'
  vellum.setup({ split = 'left', size = 30 })
  vellum.open()
  local pwin = vim.fn.bufwinid('vellum://preview')
  local pcol, scol = vim.api.nvim_win_get_position(pwin)[2], vim.api.nvim_win_get_position(src)[2]
  check('split = left, size = 30', pwin > 0 and pcol < scol and vim.api.nvim_win_get_width(pwin) == 30,
    vim.inspect({ pcol, scol, pwin > 0 and vim.api.nvim_win_get_width(pwin) }))
  vellum.close()
  vellum.setup({ split = 'below', size = 8 })
  vellum.open()
  pwin = vim.fn.bufwinid('vellum://preview')
  check('split = below, size = 8', pwin > 0 and vim.api.nvim_win_get_position(pwin)[1] > vim.api.nvim_win_get_position(src)[1]
    and vim.api.nvim_win_get_height(pwin) == 8)
  vellum.close()

  vim.api.nvim_set_hl(0, 'VellumH1', { fg = '#ff0000' })
  vellum.open()
  check("a user's Vellum* color survives opening", vim.api.nvim_get_hl(0, { name = 'VellumH1' }).fg == 0xff0000)
  vellum.close()
  local au = vim.api.nvim_create_autocmd('ColorScheme', { callback = function() vim.api.nvim_set_hl(0, 'VellumH1', { fg = '#00ff00' }) end })
  vellum.open()
  vim.cmd('colorscheme default')
  vim.wait(50)
  check("a user's Vellum* color set on ColorScheme survives a colorscheme change", vim.api.nvim_get_hl(0, { name = 'VellumH1' }).fg == 0x00ff00)
  vellum.close()
  vim.api.nvim_del_autocmd(au)
  vim.cmd('colorscheme default')
  vim.wait(50)
  check('without one, the derived color comes back', vim.api.nvim_get_hl(0, { name = 'VellumH1' }).fg ~= 0x00ff00)

  vellum.setup({ split = 'right', auto_open = true })
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].filetype = 'markdown'
  vim.api.nvim_set_current_buf(scratch) -- like a hover or picker preview: markdown, but not a file
  vim.wait(50)
  check('auto_open skips markdown that is not a file', vim.fn.bufwinid('vellum://preview') == -1)
  local file = vim.fn.tempname() .. '.md'
  vim.fn.writefile({ '# Auto' }, file)
  vim.cmd.edit(file)
  vim.wait(50)
  check('auto_open opens on a markdown file', vim.fn.bufwinid('vellum://preview') > 0)
  vellum.close()
  vellum.setup({ auto_open = false })
  vim.cmd('enew')
  vim.cmd.edit(file)
  vim.wait(50)
  check('auto_open off: nothing opens', vim.fn.bufwinid('vellum://preview') == -1)
end

print(('%d checks, %d failed'):format(count, failed))
vim.cmd(failed == 0 and 'qa!' or 'cq!')
