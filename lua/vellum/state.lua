-- Startup state shared by every module. setup() picks the backend once; it is
-- not expected to change at runtime, so modules read it instead of branching.
-- A backend provides diagram, math, image, inline, dir, reset, waiting,
-- drop_stale, configure, export, warning, health, commands, note and extension.
local M = {
  chromium = true,
  on_update = function() end,
}

function M.use(chromium)
  local previous = rawget(M, 'backend')
  M.chromium = chromium
  M.backend = require(chromium and 'vellum.backend.chromium' or 'vellum.backend.text')
  if previous and previous ~= M.backend then previous.reset() end
end

-- loaded on first use: a backend requires code.lua, which requires this module
setmetatable(M, {
  __index = function(t, k)
    if k ~= 'backend' then return end
    M.use(M.chromium)
    return rawget(t, 'backend')
  end,
})

return M
