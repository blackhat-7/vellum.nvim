-- Keystroke redraw cost on a ~5,000-line doc. Run: nvim --clean -l test/perf.lua
vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))
require('vellum.image').supported = false
local sample = vim.fn.readfile('test/sample.md')
local lines = {}
while #lines < 5000 do vim.list_extend(lines, sample) end
vim.cmd('enew')
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.bo.filetype = 'markdown'
local vellum = require('vellum')
local function ms(t) return (vim.uv.hrtime() - t) / 1e6 end

local t = vim.uv.hrtime()
vellum.open()
print(('open (cold render + draw): %.1f ms'):format(ms(t)))

local times = {}
for i = 1, 20 do
  vim.api.nvim_buf_set_text(0, 2500, 0, 2500, 0, { 'x' }) -- one keystroke mid-document
  t = vim.uv.hrtime()
  vellum.redraw()
  times[i] = ms(t)
end
table.sort(times)
print(('keystroke redraw: median %.2f ms, worst %.2f ms, %d lines'):format(times[10], times[20], #lines))
vim.cmd('qa!')
