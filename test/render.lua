-- Renderer check: draws every diagram in test/diagrams.md and test/d2.md,
-- the display math in test/sample.md and test/images/* with the real
-- renderer, then exports a document with diagrams to HTML and PDF.
-- Run: nvim --clean -l test/render.lua [--update]   (needs the built renderer)
-- D2, KaTeX and images carry their own fonts or pixels, so their PNG sizes
-- must match test/render.sizes; --update rewrites the entries for the
-- renderers present. Mermaid uses the system's fonts, so it only has to render.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.env.XDG_CACHE_HOME = vim.fn.tempname() -- a fresh cache: everything renders
local browser, theme = require('vellum.browser'), require('vellum.theme')
theme.apply()
local failed = 0
local function fail(msg)
  failed = failed + 1
  print('FAIL ' .. msg)
end

-- The code of each `lang` fence in `file`, and whether the line above says
-- it is broken on purpose (it must fail then).
local function fences(file, lang)
  local out = {}
  local text = '\n' .. table.concat(vim.fn.readfile(root .. '/' .. file), '\n')
  for above, code in text:gmatch('\n([^\n]*)\n```' .. lang .. '\n(.-)```') do
    out[#out + 1] = { code, above:find('broken on purpose') ~= nil }
  end
  return out
end

-- { label, group, ask }; group names whose sizes are compared, nil for mermaid
local jobs = {}
local d2 = browser.d2_command()
local d2_group = d2 and 'd2 ' .. d2.version or 'bundled d2'
for i, f in ipairs(fences('test/diagrams.md', 'mermaid')) do
  jobs[#jobs + 1] = { label = 'mermaid ' .. i, broken = f[2], ask = function() return browser.diagram(f[1], theme, 'mermaid') end }
end
for i, f in ipairs(fences('test/d2.md', 'd2')) do
  jobs[#jobs + 1] = { label = d2_group .. ' ' .. i, group = d2_group, broken = f[2], ask = function() return browser.diagram(f[1], theme, 'd2', root .. '/test') end }
end
for i, f in ipairs(fences('test/sample.md', 'math')) do
  jobs[#jobs + 1] = { label = 'math ' .. i, group = 'katex', broken = f[2], ask = function() return browser.math(f[1], theme.math) end }
end
for _, file in ipairs(vim.fn.glob(root .. '/test/images/*', false, true)) do
  jobs[#jobs + 1] = { label = 'image ' .. vim.fs.basename(file), group = 'images', ask = function() return browser.image(file, 'check') end }
end

-- all requests go out at once and the renderer queues them; asking again
-- only reads the state of one already sent
local t0 = vim.uv.hrtime()
vim.wait(300000, function()
  local busy = false
  for _, j in ipairs(jobs) do
    if j.state == nil or j.state == 'pending' then j.state, j.a, j.b = j.ask() end
    busy = busy or j.state == 'pending'
  end
  return not busy
end, 50)

local file = root .. '/test/render.sizes'
local saved, groups = {}, {}
for _, line in ipairs(vim.uv.fs_stat(file) and vim.fn.readfile(file) or {}) do
  local group, label, size = line:match('^(.-)\t(.-)\t(.-)$')
  if group then saved[label] = { group = group, size = size } end
end
for _, j in ipairs(jobs) do
  if j.broken then
    if j.state ~= 'error' then fail(j.label .. ': broken on purpose, but ' .. j.state) end
  elseif j.state ~= 'ready' then
    fail(j.label .. ': ' .. (j.state == 'error' and j.a or 'no answer'))
  elseif j.group then
    groups[j.group] = true
    local size = j.b[1] .. 'x' .. j.b[2]
    if arg[1] == '--update' then
      saved[j.label] = { group = j.group, size = size }
    elseif not saved[j.label] then
      print(('NOTE %s: %s, not in test/render.sizes (--update adds it)'):format(j.label, size))
    elseif saved[j.label].size ~= size then
      fail(('%s: %s, was %s'):format(j.label, size, saved[j.label].size))
    end
  end
end
if arg[1] == '--update' then
  local out = {}
  for label, s in pairs(saved) do out[#out + 1] = s.group .. '\t' .. label .. '\t' .. s.size end
  table.sort(out)
  vim.fn.writefile(out, file)
end

-- export: diagrams become pictures, a broken one stays as its code
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
local doc = '# Export\n\n```mermaid\ngraph LR; A --> B\n```\n\n```d2\nx -> y\n```\n\n```d2\nx ->\n```\n'
for _, ext in ipairs({ 'html', 'pdf' }) do
  local out, done, err = dir .. '/doc.' .. ext, false, nil
  browser.export({ markdown = doc, dir = dir, out = out, kinds = {} }, function(e) done, err = true, e end)
  vim.wait(60000, function() return done end, 50)
  if not done or err then fail('export ' .. ext .. ': ' .. (err or 'no answer')) end
end
local html = table.concat(vim.fn.readfile(dir .. '/doc.html'), '\n')
local count = function(pat) return select(2, html:gsub(pat, '')) end
if count('class="mermaid"') ~= 1 or count('class="diagram"') ~= 1 or count('language%-d2') ~= 1 then
  fail('export html: mermaid, D2 and broken D2 not as expected')
end
if (vim.uv.fs_stat(dir .. '/doc.pdf') or { size = 0 }).size == 0 then fail('export pdf: empty') end

-- diagrams = false: mermaid and D2 stay as code in the export
browser.diagrams = false
local plain, done, err = dir .. '/plain.html', false, nil
browser.export({ markdown = doc, dir = dir, out = plain, kinds = {} }, function(e) done, err = true, e end)
vim.wait(60000, function() return done end, 50)
browser.diagrams = true
local code = done and not err and table.concat(vim.fn.readfile(plain), '\n') or ''
local n = function(pat) return select(2, code:gsub(pat, '')) end
if code == '' or n('language%-mermaid') ~= 1 or n('language%-d2') ~= 2 or n('class="mermaid"') ~= 0 or n('class="diagram"') ~= 0 then
  fail('export with diagrams off: diagrams not left as code' .. (err and (': ' .. err) or ''))
end

print(('%d pictures and 2 exports in %.1f s, %d failed'):format(#jobs, (vim.uv.hrtime() - t0) / 1e9, failed))
vim.cmd(failed == 0 and 'qa!' or 'cq!')
