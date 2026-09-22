-- Minimal config for manual and screenshot checks: nvim --clean -u test/init.lua
vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))
vim.o.termguicolors = true
local theme = (vim.env.THEME or '') ~= '' and vim.env.THEME or 'rose-pine'
local path = vim.fn.stdpath('data') .. '/lazy/' .. theme
if vim.uv.fs_stat(path) then vim.opt.rtp:append(path); pcall(vim.cmd.colorscheme, theme) end
