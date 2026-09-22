-- Images as placeholder lines: local PNGs go straight to the terminal, other
-- formats and remote images through the headless browser.
local image = require('vellum.image')
local browser = require('vellum.browser')

local M = {}

M.dir = '.' -- directory of the markdown file, for relative paths
M.pending = 0 -- bumped by output still being rendered, which must not be cached

-- An image centered in `width`; `density` is image pixels per CSS pixel.
function M.picture(file, pw, ph, width, density)
  local cw, ch = image.cell()
  -- natural size puts 16px diagram text near terminal text size; shrink to
  -- fit, but not below 75% of that: past it, scroll sideways like a wide table
  local natural = pw / density * ch / 24 / cw
  local cols = math.ceil(math.min(natural, math.max(width, 0.75 * natural)))
  cols = math.max(1, math.min(cols, image.max_cells))
  local rows = math.max(1, math.floor(cols * cw * ph / pw / ch + 0.5))
  if rows > image.max_cells then
    rows = image.max_cells
    cols = math.max(1, math.floor(rows * ch * pw / ph / cw))
  end
  local pad = { string.rep(' ', math.max(0, math.floor((width - cols) / 2))) }
  local out = {}
  for i, l in ipairs(image.lines(file, cols, rows)) do out[i] = { pad, l[1] } end
  return out
end

-- Lines showing image `src` (local path or http(s) URL), or nil to fall back
-- to its alt text.
function M.image(src, width)
  if not image.supported or image.problem then return nil end
  local remote, version = src:match('^https?://'), os.date('%F') -- remote images refresh daily
  if not remote then
    if src:match('^%a[%w+.-]*:') then return nil end
    src = vim.fs.normalize(src:sub(1, 1) == '/' and src or M.dir .. '/' .. src)
    local stat = vim.uv.fs_stat(src)
    if not stat or stat.type ~= 'file' then return nil end
    if src:lower():match('%.png$') then
      local pw, ph = image.png_size(src)
      return pw and M.picture(src, pw, ph, width, 1)
    end
    version = stat.mtime.sec .. '.' .. stat.size
  end
  local state, file, size = browser.image(src, version)
  if state == 'ready' then return M.picture(file, size[1], size[2], width, 2) end
  if state == 'pending' then M.pending = M.pending + 1 end
  return nil
end

return M
