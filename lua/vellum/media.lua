-- Images as placeholder lines: local PNGs go straight to the terminal, other
-- formats and remote images through the headless browser.
local image = require('vellum.image')
local browser = require('vellum.browser')

local M = {}

M.dir = '.' -- directory of the markdown file, for relative paths
M.pending = 0 -- bumped by output still being rendered, which must not be cached

local ROW = 24 -- CSS px per text row: 16px text in an image lands near terminal text size

-- An image centered in `width`; `density` is image pixels per CSS pixel.
function M.picture(file, pw, ph, width, density)
  local cw, ch = image.cell()
  -- natural size, shrunk to fit: an image wider than the pane shows only its
  -- left edge, often empty, and scroll sync resets sideways scrolling anyway
  local natural = pw / density * ch / ROW / cw
  local cols = math.max(1, math.min(math.ceil(math.min(natural, width)), image.max_cells))
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

-- The PNG showing image `src` (local path or http(s) URL): file, width,
-- height, density. Nil while it renders or when it cannot be shown.
local function load(src)
  if not image.supported or image.problem then return nil end
  local remote, version = src:match('^https?://'), os.date('%F') -- remote images refresh daily
  if not remote then
    if src:match('^%a[%w+.-]*:') then return nil end
    src = vim.fs.normalize(src:sub(1, 1) == '/' and src or M.dir .. '/' .. src)
    local stat = vim.uv.fs_stat(src)
    if not stat or stat.type ~= 'file' then return nil end
    if src:lower():match('%.png$') then
      local pw, ph = image.png_size(src)
      return pw and src, pw, ph, 1
    end
    version = stat.mtime.sec .. '.' .. stat.size
  end
  local state, file, size = browser.image(src, version)
  if state == 'ready' then return file, size[1], size[2], 2 end
  if state == 'pending' then M.pending = M.pending + 1 end
end

-- Lines showing image `src` as a block, or nil.
function M.image(src, width)
  local file, pw, ph, density = load(src)
  return file and M.picture(file, pw, ph, width, density)
end

-- A small image (badge, icon) as one segment one text row high, to sit in a
-- line of text. Nil when it is not ready or taller than about one row.
function M.inline(src)
  local file, pw, ph, density = load(src)
  if not file or ph / density > 1.5 * ROW then return nil end
  local cw, ch = image.cell()
  local cols = math.max(1, math.min(image.max_cells, math.floor(pw / ph * ch / cw + 0.5)))
  return image.lines(file, cols, 1)[1][1]
end

return M
