-- Kitty graphics via Unicode placeholders. The image is sent once; the buffer
-- then holds ordinary placeholder text whose fg color is the image id, so it
-- scrolls, clips and survives tmux like any other text.
local M = {}

-- Row/column index diacritics, from kitty's rowcolumn-diacritics.txt.
local DIACRITICS = {
  0x0305, 0x030D, 0x030E, 0x0310, 0x0312, 0x033D, 0x033E, 0x033F, 0x0346, 0x034A, 0x034B, 0x034C,
  0x0350, 0x0351, 0x0352, 0x0357, 0x035B, 0x0363, 0x0364, 0x0365, 0x0366, 0x0367, 0x0368, 0x0369,
  0x036A, 0x036B, 0x036C, 0x036D, 0x036E, 0x036F, 0x0483, 0x0484, 0x0485, 0x0486, 0x0487, 0x0592,
  0x0593, 0x0594, 0x0595, 0x0597, 0x0598, 0x0599, 0x059C, 0x059D, 0x059E, 0x059F, 0x05A0, 0x05A1,
  0x05A8, 0x05A9, 0x05AB, 0x05AC, 0x05AF, 0x05C4, 0x0610, 0x0611, 0x0612, 0x0613, 0x0614, 0x0615,
  0x0616, 0x0617, 0x0657, 0x0658, 0x0659, 0x065A, 0x065B, 0x065D, 0x065E, 0x06D6, 0x06D7, 0x06D8,
  0x06D9, 0x06DA, 0x06DB, 0x06DC, 0x06DF, 0x06E0, 0x06E1, 0x06E2, 0x06E4, 0x06E7, 0x06E8, 0x06EB,
  0x06EC, 0x0730, 0x0732, 0x0733, 0x0735, 0x0736, 0x073A, 0x073D, 0x073F, 0x0740, 0x0741, 0x0743,
  0x0745, 0x0747, 0x0749, 0x074A, 0x07EB, 0x07EC, 0x07ED, 0x07EE, 0x07EF, 0x07F0, 0x07F1, 0x07F3,
  0x0816, 0x0817, 0x0818, 0x0819, 0x081B, 0x081C, 0x081D, 0x081E, 0x081F, 0x0820, 0x0821, 0x0822,
  0x0823, 0x0825, 0x0826, 0x0827, 0x0829, 0x082A, 0x082B, 0x082C, 0x082D, 0x0951, 0x0953, 0x0954,
  0x0F82, 0x0F83, 0x0F86, 0x0F87, 0x135D, 0x135E, 0x135F, 0x17DD, 0x193A, 0x1A17, 0x1A75, 0x1A76,
  0x1A77, 0x1A78, 0x1A79, 0x1A7A, 0x1A7B, 0x1A7C, 0x1B6B, 0x1B6D, 0x1B6E, 0x1B6F, 0x1B70, 0x1B71,
  0x1B72, 0x1B73, 0x1CD0, 0x1CD1, 0x1CD2, 0x1CDA, 0x1CDB, 0x1CE0, 0x1DC0, 0x1DC1, 0x1DC3, 0x1DC4,
  0x1DC5, 0x1DC6, 0x1DC7, 0x1DC8, 0x1DC9, 0x1DCB, 0x1DCC, 0x1DD1, 0x1DD2, 0x1DD3, 0x1DD4, 0x1DD5,
  0x1DD6, 0x1DD7, 0x1DD8, 0x1DD9, 0x1DDA, 0x1DDB, 0x1DDC, 0x1DDD, 0x1DDE, 0x1DDF, 0x1DE0, 0x1DE1,
  0x1DE2, 0x1DE3, 0x1DE4, 0x1DE5, 0x1DE6, 0x1DFE, 0x20D0, 0x20D1, 0x20D4, 0x20D5, 0x20D6, 0x20D7,
  0x20DB, 0x20DC, 0x20E1, 0x20E7, 0x20E9, 0x20F0, 0x2CEF, 0x2CF0, 0x2CF1, 0x2DE0, 0x2DE1, 0x2DE2,
  0x2DE3, 0x2DE4, 0x2DE5, 0x2DE6, 0x2DE7, 0x2DE8, 0x2DE9, 0x2DEA, 0x2DEB, 0x2DEC, 0x2DED, 0x2DEE,
  0x2DEF, 0x2DF0, 0x2DF1, 0x2DF2, 0x2DF3, 0x2DF4, 0x2DF5, 0x2DF6, 0x2DF7, 0x2DF8, 0x2DF9, 0x2DFA,
  0x2DFB, 0x2DFC, 0x2DFD, 0x2DFE, 0x2DFF, 0xA66F, 0xA67C, 0xA67D, 0xA6F0, 0xA6F1, 0xA8E0, 0xA8E1,
  0xA8E2, 0xA8E3, 0xA8E4, 0xA8E5, 0xA8E6, 0xA8E7, 0xA8E8, 0xA8E9, 0xA8EA, 0xA8EB, 0xA8EC, 0xA8ED,
  0xA8EE, 0xA8EF, 0xA8F0, 0xA8F1, 0xAAB0, 0xAAB2, 0xAAB3, 0xAAB7, 0xAAB8, 0xAABE, 0xAABF, 0xAAC1,
  0xFE20, 0xFE21, 0xFE22, 0xFE23, 0xFE24, 0xFE25, 0xFE26, 0x10A0F, 0x10A38, 0x1D185, 0x1D186,
  0x1D187, 0x1D188, 0x1D189, 0x1D1AA, 0x1D1AB, 0x1D1AC, 0x1D1AD, 0x1D242, 0x1D243, 0x1D244,
}

local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)
M.max_cells = #DIACRITICS -- per row and per column

-- Which terminal draws the images, and whether it can. Inside tmux (often
-- over ssh, where env vars lie) tmux reports the attached terminal. tmux also
-- downgrades 24-bit color unless told the terminal has it, and a placeholder's
-- color *is* its image id, so without RGB images would silently vanish.
local function detect()
  local env = (vim.env.TERM or '') .. (vim.env.TERM_PROGRAM or '')
  local local_term = vim.env.KITTY_WINDOW_ID or vim.env.GHOSTTY_RESOURCES_DIR or env:find('kitty') or env:find('ghostty')
  local client = ''
  if vim.env.TMUX then
    local ok, r = pcall(function()
      return vim.system({ 'tmux', 'display', '-p', '#{client_termtype}\t#{client_termfeatures}\t#{client_termname}' }, { text = true }):wait()
    end)
    client = ok and r.code == 0 and r.stdout or ''
  end
  local kind, features, name = unpack(vim.split(vim.trim(client), '\t'))
  M.supported = vim.api.nvim_ui_send ~= nil
    and (local_term or (kind or ''):lower():find('kitty') or (kind or ''):lower():find('ghostty')) ~= nil
  M.problem = nil
  if M.supported and vim.env.TMUX and features and not features:find('RGB') then
    M.problem = ("tmux isn't passing 24-bit color, so images can't show. Add to tmux.conf:\nset -as terminal-features ',%s:RGB'\nthen detach and re-attach."):format(name or 'xterm-256color')
  end
end
detect()

local sent = {}
local ffi = require('ffi')
pcall(ffi.cdef, 'struct vellum_ws { unsigned short row, col, xpixel, ypixel; }; int ioctl(int, unsigned long, ...);') -- pcall: survives a module reload

local function send(seq)
  -- tmux forwards only DCS-wrapped sequences, with inner ESCs doubled
  if vim.env.TMUX then seq = '\27Ptmux;' .. seq:gsub('\27', '\27\27') .. '\27\\' end
  vim.api.nvim_ui_send(seq)
end

-- Forget what was sent and look at the terminal again, e.g. after tmux
-- re-attaches from another terminal.
function M.reset()
  sent = {}
  detect()
end

-- Send the PNG bytes themselves, not a path: over ssh the terminal is on
-- another machine and cannot read our files.
local function transmit(id, cols, rows, path)
  local f = io.open(path, 'rb')
  if not f then return end
  local data = vim.base64.encode(f:read('*a'))
  f:close()
  for i = 1, #data, 4096 do
    local more = i + 4096 <= #data and 1 or 0
    local keys = i == 1 and ('a=T,f=100,U=1,q=2,i=%d,c=%d,r=%d,m=%d'):format(id, cols, rows, more) or 'm=' .. more
    send('\27_G' .. keys .. ';' .. data:sub(i, i + 4095) .. '\27\\')
  end
end

-- Pixel size of one terminal cell.
function M.cell()
  local ws = ffi.new('struct vellum_ws')
  local req = jit.os == 'OSX' and 0x40087468 or 0x5413 -- TIOCGWINSZ
  if ffi.C.ioctl(1, req, ws) == 0 and ws.xpixel > 0 and ws.col > 0 then
    return ws.xpixel / ws.col, ws.ypixel / ws.row
  end
  return 8, 16
end

-- Width and height of a PNG file, or nil when it is missing.
function M.png_size(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local h = f:read(24)
  f:close()
  if not h or #h < 24 or h:sub(2, 4) ~= 'PNG' then return nil end
  local function u32(i)
    local a, b, c, d = h:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return u32(17), u32(21)
end

-- Placeholder lines showing `path` in a cols x rows box, as segment lines.
function M.lines(path, cols, rows)
  local id = tonumber(vim.fn.sha256(path .. cols .. 'x' .. rows):sub(1, 6), 16)
  if id == 0 then id = 1 end
  local hl = 'VellumImg' .. id
  vim.api.nvim_set_hl(0, hl, { fg = id })
  if not sent[id] then
    sent[id] = true
    transmit(id, cols, rows, path)
  end
  -- every cell names its row and column, so an image scrolled sideways
  -- (wider than the window) still draws the right slice
  local col = {}
  for c = 1, cols do col[c] = vim.fn.nr2char(DIACRITICS[c]) end
  local out = {}
  for r = 1, rows do
    local cell = PLACEHOLDER .. vim.fn.nr2char(DIACRITICS[r])
    local parts = {}
    for c = 1, cols do parts[c] = cell .. col[c] end
    out[r] = { { table.concat(parts), hl } }
  end
  return out
end

return M
