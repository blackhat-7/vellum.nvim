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
  vellum.close()
end

-- images: a small one stays centered at natural size, a very wide one
-- shrinks to the width (overflowing, it showed only its empty left edge)
do
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local function png(name, w, h) -- only the header is read for the size
    local function u32(n) return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) end
    local f = io.open(dir .. '/' .. name, 'wb')
    f:write('\137PNG\r\n\26\n' .. u32(13) .. 'IHDR' .. u32(w) .. u32(h))
    f:close()
  end
  png('wide.png', 9000, 600)
  png('small.png', 200, 100)
  png('badge.png', 80, 20)
  image.supported, image.problem = true, nil
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
end

-- image placeholders are exactly cols wide
do
  local lines = image.lines('/nonexistent.png', 7, 3)
  check('placeholder rows', #lines == 3)
  check('placeholder cols', vim.api.nvim_strwidth(lines[2][1][1]) == 7)
end

print(('%d checks, %d failed'):format(count, failed))
vim.cmd(failed == 0 and 'qa!' or 'cq!')
