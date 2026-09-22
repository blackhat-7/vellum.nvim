-- lazy.nvim runs this on install and update: it installs the mermaid renderer.
local dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/render'
for _, cmd in ipairs({ { 'npm', 'ci' }, { 'npx', 'puppeteer', 'browsers', 'install', 'chrome-headless-shell' } }) do
  local r = vim.system(cmd, { cwd = dir }):wait()
  if r.code ~= 0 then error(table.concat(cmd, ' ') .. ' failed:\n' .. r.stderr) end
end
