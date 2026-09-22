-- Assertion tests. Run: nvim --clean -l test/run.lua
vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))
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

-- no line is wider than the window, at any width
for _, w in ipairs({ 24, 40, 57, 80, 84, 121, 200 }) do
  local lines = doc(sample, w)
  for i, l in ipairs(lines) do
    local sw = vim.api.nvim_strwidth(l)
    if sw > w then check('width ' .. w, false, ('line %d is %d wide: %s'):format(i, sw, l)) break end
  end
end

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
  check('ordered start', find(doc('7. a\n8. b'), '7%. a'))
  check('task list', find(doc('- [x] done'), '󰄵 done'))
  local l, rows = doc('go to https://a.b/c. now')
  local i = find(l, 'https://a.b/c%. now')
  local m = i and rows[i] and rows[i][1]
  check('bare url is a link, minus the period', m and m[3] == 'VellumLink' and l[i]:sub(m[1] + 3, m[2] + 2) == 'https://a.b/c', vim.inspect(m))
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
  check('alert color', style('> [!TIP]\n> x', 'Tip'):find('Tip'), style('> [!TIP]\n> x', 'Tip'))
end

-- image placeholders are exactly cols wide
do
  local lines = image.lines('/nonexistent.png', 7, 3)
  check('placeholder rows', #lines == 3)
  check('placeholder cols', vim.api.nvim_strwidth(lines[2][1][1]) == 7)
end

print(('%d checks, %d failed'):format(count, failed))
vim.cmd(failed == 0 and 'qa!' or 'cq!')
