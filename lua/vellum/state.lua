-- Startup state shared by every module. setup() picks the backend once; it is
-- not expected to change at runtime, so modules read it instead of branching.
local M = {
  chromium = true,
  on_update = function() end,
}

function M.use(chromium)
  M.chromium = chromium
  M.backend = require(chromium and 'vellum.backend.chromium' or 'vellum.backend.text')
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
