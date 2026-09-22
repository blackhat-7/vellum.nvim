-- Render many real markdown files and report problems.
-- Run: nvim --clean -l test/sweep.lua <file-with-one-path-per-line> [out.tsv]
-- Per unique file and width: crash, a line wider than the window (tables
-- excepted), and source words missing from the preview (silently dropped text).
vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))
local render = require('vellum.render')
require('vellum.image').supported = false -- no browser: diagrams show as code, so their text is checked too
require('vellum.theme').apply()

local list, out = arg[1], arg[2]
local report = {}
local function problem(kind, path, detail) report[#report + 1] = table.concat({ kind, path, detail or '' }, '\t') end

-- Words a reader should find in the preview: link targets, HTML tags,
-- comments and link definitions are markup, not content.
local function words(text)
  text = text:gsub('<!%-%-.-%-%->', ' ')
    :gsub('%]%b()', ']')
    :gsub('%]%[[^%]\n]*%]', ']')
    :gsub('<img[^>]-alt="([^"]*)"[^>]*>', ' %1 ')
    :gsub('</?%a[^>]*>', ' ')
    :gsub('\n%s*%[[^%]\n]+%]:[^\n]*', '\n')
    :gsub('&%a+;', ' ')
  local seen, list = {}, {}
  for w in text:gmatch('%a[%w_]+') do
    w = w:gsub('_+$', '') -- "_word_" emphasis
    if #w >= 4 and not seen[w] then
      seen[w] = true
      list[#list + 1] = w
    end
  end
  return list
end

local seen, files, slow = {}, 0, {}
for path in io.lines(list) do
  local f = io.open(path, 'rb')
  local text = f and f:read('*a')
  if f then f:close() end
  local key = text and #text < 2e6 and vim.fn.sha256(text)
  if key and not seen[key] then
    seen[key] = true
    files = files + 1
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text:gsub('\r\n', '\n'), '\n'))
    for _, w in ipairs({ 60, 100, 150 }) do
      render.reset()
      local t = vim.uv.hrtime()
      local ok, lines = pcall(render.render, buf, w, 100)
      local ms = (vim.uv.hrtime() - t) / 1e6
      if not ok then
        problem('crash', path, w .. ': ' .. tostring(lines):gsub('\n', ' '))
        break
      end
      if w == 100 and ms > 50 then slow[#slow + 1] = { ms, path } end
      for i, l in ipairs(lines) do
        if vim.api.nvim_strwidth(l) > w and not l:find('[│╭╰├]') then
          problem('overflow', path, ('%d: line %d is %d wide'):format(w, i, vim.api.nvim_strwidth(l)))
          break
        end
      end
      if w == 100 then
        local shown = table.concat(lines):gsub('%s', ''):lower()
        local missing = {}
        for _, word in ipairs(words(text)) do
          if not shown:find(word:lower(), 1, true) then missing[#missing + 1] = word end
        end
        if #missing > 0 then problem('missing', path, #missing .. ': ' .. table.concat(missing, ' ', 1, math.min(#missing, 8))) end
      end
    end
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

table.sort(slow, function(a, b) return a[1] > b[1] end)
for i = 1, math.min(5, #slow) do problem('slow', slow[i][2], ('%.0f ms'):format(slow[i][1])) end
if out then vim.fn.writefile(report, out) end
local counts = {}
for _, r in ipairs(report) do
  local k = r:match('^%a+')
  counts[k] = (counts[k] or 0) + 1
end
print(('%d unique files: %s'):format(files, vim.inspect(counts)))
vim.cmd('qa!')
