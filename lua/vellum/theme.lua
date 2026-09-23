-- Palette derived from the active colorscheme, so the preview and the
-- diagrams always match the editor. Tints are blends toward the background.
local M = {}

local function get(name, attr)
  return vim.api.nvim_get_hl(0, { name = name, link = false })[attr]
end

local function blend(a, b, t) -- t = weight of a
  local r = 0
  for shift = 16, 0, -8 do
    local x, y = math.floor(a / 2 ^ shift) % 256, math.floor(b / 2 ^ shift) % 256
    r = r + math.floor(x * t + y * (1 - t) + 0.5) * 2 ^ shift
  end
  return r
end

local hex = function(c) return ('#%06x'):format(c) end

M.FADE = 8 -- steps in a gradient rule
local merged = {}

function M.apply()
  merged = {}
  local dark = vim.o.background == 'dark'
  local bg = get('Normal', 'bg') or (dark and 0x16161e or 0xfbfbfd)
  local fg = get('Normal', 'fg') or (dark and 0xd8dae5 or 0x2a2c35)
  local function pick(...)
    for _, n in ipairs({ ... }) do
      local c = get(n, 'fg')
      if c and c ~= fg then return c end
    end
    return fg
  end
  local h = {
    pick('Function', 'Title'), pick('Statement', 'Keyword'), pick('String'),
    pick('Type'), pick('Constant', 'Number'), pick('Special', 'Identifier'),
  }
  local muted = get('Comment', 'fg') or blend(fg, bg, 0.5)
  local border = blend(fg, bg, 0.22)
  local ok, info, warn, err = pick('DiagnosticOk', 'String'), pick('DiagnosticInfo'), pick('DiagnosticWarn'), pick('DiagnosticError')
  local set = function(name, v) vim.api.nvim_set_hl(0, 'Vellum' .. name, v) end

  for i, c in ipairs(h) do set('H' .. i, { fg = c, bold = i < 6, italic = i >= 5 }) end
  set('H1Band', { fg = h[1], bg = blend(h[1], bg, 0.16), bold = true })
  set('Text', { fg = fg })
  set('Muted', { fg = muted })
  set('Border', { fg = border })
  set('Bold', { bold = true })
  set('Italic', { italic = true })
  set('Strike', { strikethrough = true, fg = muted })
  set('Code', { fg = h[5], bg = blend(fg, bg, 0.09) })
  set('CodeBg', { bg = blend(fg, bg, 0.05) })
  set('CodeLabel', { fg = muted, bg = blend(fg, bg, 0.05), italic = true })
  set('Link', { fg = h[1], underline = true, sp = blend(h[1], bg, 0.5) })
  set('Bullet', { fg = h[1], bold = true })
  set('Done', { fg = ok })
  set('Todo', { fg = muted })
  set('Quote', { fg = blend(fg, bg, 0.72), italic = true })
  set('QuoteBar', { fg = border })
  set('TableHead', { fg = h[1], bg = blend(h[1], bg, 0.1), bold = true })
  set('TableRow', { bg = blend(fg, bg, 0.035) })
  set('Error', { fg = err })
  for name, c in pairs({ Note = info, Tip = ok, Important = h[2], Warning = warn, Caution = err }) do
    set(name, { fg = c, bold = true })
  end
  for k = 1, M.FADE do
    set('Fade' .. k, { fg = blend(h[1], bg, k / M.FADE) })
    set('FadeMuted' .. k, { fg = blend(border, bg, k / M.FADE) })
  end

  -- mermaid themeVariables; derived colors fill the rest
  M.mermaid = {
    darkMode = dark, background = hex(bg), fontSize = '16px',
    primaryColor = hex(blend(h[1], bg, 0.18)), primaryTextColor = hex(fg), primaryBorderColor = hex(h[1]),
    secondaryColor = hex(blend(h[2], bg, 0.18)), tertiaryColor = hex(blend(fg, bg, 0.06)),
    lineColor = hex(muted), textColor = hex(fg), titleColor = hex(fg), edgeLabelBackground = hex(bg),
    clusterBkg = hex(blend(fg, bg, 0.04)), clusterBorder = hex(border),
    noteBkgColor = hex(blend(h[4], bg, 0.2)), noteTextColor = hex(fg), noteBorderColor = hex(h[4]),
    actorBkg = hex(blend(h[1], bg, 0.18)), actorBorder = hex(h[1]), actorTextColor = hex(fg),
    signalColor = hex(fg), signalTextColor = hex(fg), labelTextColor = hex(fg),
    sectionBkgColor = hex(blend(h[1], bg, 0.08)), sectionBkgColor2 = hex(blend(h[2], bg, 0.08)),
    altSectionBkgColor = hex(bg), gridColor = hex(border), taskBkgColor = hex(blend(h[1], bg, 0.35)),
    taskBorderColor = hex(h[1]), taskTextColor = hex(fg), taskTextOutsideColor = hex(fg),
    taskTextLightColor = hex(fg), taskTextDarkColor = hex(fg), activeTaskBkgColor = hex(blend(h[3], bg, 0.35)),
    activeTaskBorderColor = hex(h[3]), doneTaskBkgColor = hex(blend(muted, bg, 0.35)),
    doneTaskBorderColor = hex(muted), todayLineColor = hex(h[5]),
    pieStrokeColor = hex(bg), pieOuterStrokeColor = hex(border), pieTitleTextColor = hex(fg),
    pieLegendTextColor = hex(fg), pieSectionTextColor = hex(bg),
  }
  for i, c in ipairs(h) do M.mermaid['pie' .. i] = hex(c) end
  -- mindmap, timeline and gitGraph cycle through these scales
  for i = 0, 11 do
    local c = h[i % #h + 1]
    M.mermaid['cScale' .. i] = hex(blend(c, bg, 0.3))
    M.mermaid['cScaleLabel' .. i] = hex(fg)
    M.mermaid['cScalePeer' .. i] = hex(c)
    if i < 8 then
      M.mermaid['git' .. i] = hex(c)
      M.mermaid['gitBranchLabel' .. i] = hex(bg)
    end
  end
  -- sorted: table order changes between sessions, and this is part of the disk cache key
  M.signature = vim.json.encode(M.mermaid, { sort_keys = true })
end

-- One highlight group combining `groups` in order, later ones winning.
function M.merge(groups)
  if type(groups) == 'string' or #groups < 2 then return type(groups) == 'string' and groups or groups[1] end
  local name = 'Vellum_' .. table.concat(groups, '_'):gsub('Vellum', '')
  if not merged[name] then
    local attrs = {}
    for _, g in ipairs(groups) do
      for k, v in pairs(vim.api.nvim_get_hl(0, { name = g, link = false })) do attrs[k] = v end
    end
    vim.api.nvim_set_hl(0, name, attrs)
    merged[name] = true
  end
  return name
end

return M
