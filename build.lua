-- lazy.nvim runs this on install and update: it installs the browser renderer
-- (mermaid diagrams and non-PNG images). :Vellum build runs the same steps in
-- a terminal, from the command list in lua/vellum/build.lua.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
for _, cmd in ipairs(dofile(root .. '/lua/vellum/build.lua').commands) do
  local r = vim.system(cmd, { cwd = root .. '/render' }):wait()
  if r.code ~= 0 then error(table.concat(cmd, ' ') .. ' failed:\n' .. r.stderr) end
end
