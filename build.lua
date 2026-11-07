-- lazy.nvim runs this on install and update: it installs the renderer's node
-- dependencies. The browser is not downloaded here, because it cannot see
-- setup's `chromium` option: :Vellum build fetches it when Chromium is on.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
local step = dofile(root .. '/lua/vellum/install.lua').deps
local r = vim.system(step, { cwd = root .. '/render' }):wait()
if r.code ~= 0 then error(table.concat(step, ' ') .. ' failed:\n' .. r.stderr) end
