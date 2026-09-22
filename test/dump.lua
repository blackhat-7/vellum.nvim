-- Headless render: prints the preview text of test/sample.md.
vim.opt.rtp:prepend('.')
vim.cmd('edit ' .. (vim.env.FILE or 'test/sample.md'))
local theme = require('vellum.theme')
theme.apply()
local t = vim.uv.hrtime()
local lines, marks, anchors = require('vellum.render').render(0, tonumber(vim.env.W or 80), 100)
local ms = (vim.uv.hrtime() - t) / 1e6
io.stdout:write(table.concat(lines, '\n'), '\n')
io.stdout:write(('-- %d lines, %d marks, %d anchors, %.1f ms\n'):format(#lines, #marks, #anchors, ms))
local t2 = vim.uv.hrtime()
require('vellum.render').render(0, tonumber(vim.env.W or 80), 100)
io.stdout:write(('-- cached re-render %.2f ms\n'):format((vim.uv.hrtime() - t2) / 1e6))
