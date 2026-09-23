-- LaTeX math: Unicode text for inline math ("\alpha^2" → "α²"), KaTeX
-- pictures for display math. The text is also what display math shows while
-- its picture renders, and in terminals without images.
local image = require('vellum.image')
local browser = require('vellum.browser')
local theme = require('vellum.theme')
local media = require('vellum.media')

local M = {}

local CHAR = '[%z\1-\127\194-\244][\128-\191]*'

-- command → { text, class }. The class spaces atoms as TeX does: 'rel' and
-- 'bin' get spaces around them, 'op' before its operand, 'punct' after.
local SYM = {}
local function add(class, list)
  for name, text in pairs(list) do SYM[name] = { text, class } end
end
add('ord', {
  alpha = 'α', beta = 'β', gamma = 'γ', delta = 'δ', epsilon = 'ϵ', varepsilon = 'ε', zeta = 'ζ', eta = 'η',
  theta = 'θ', vartheta = 'ϑ', iota = 'ι', kappa = 'κ', lambda = 'λ', mu = 'μ', nu = 'ν', xi = 'ξ', pi = 'π',
  rho = 'ρ', varrho = 'ϱ', sigma = 'σ', varsigma = 'ς', tau = 'τ', upsilon = 'υ', phi = 'ϕ', varphi = 'φ',
  chi = 'χ', psi = 'ψ', omega = 'ω', Gamma = 'Γ', Delta = 'Δ', Theta = 'Θ', Lambda = 'Λ', Xi = 'Ξ', Pi = 'Π',
  Sigma = 'Σ', Upsilon = 'Υ', Phi = 'Φ', Psi = 'Ψ', Omega = 'Ω',
  infty = '∞', partial = '∂', nabla = '∇', forall = '∀', exists = '∃', nexists = '∄', emptyset = '∅',
  varnothing = '∅', aleph = 'ℵ', hbar = 'ℏ', ell = 'ℓ', Re = 'ℜ', Im = 'ℑ', angle = '∠', triangle = '△',
  prime = '′', backslash = '\\', top = '⊤', bot = '⊥', ldots = '…', dots = '…', cdots = '⋯', vdots = '⋮',
  ddots = '⋱', degree = '°', neg = '¬', lnot = '¬', dagger = '†', vert = '|', Vert = '‖', ['|'] = '‖',
  ['$'] = '$', ['%'] = '%', ['&'] = '&', ['#'] = '#', ['_'] = '_',
})
add('bin', {
  pm = '±', mp = '∓', times = '×', div = '÷', cdot = '⋅', ast = '∗', star = '⋆', circ = '∘', bullet = '∙',
  oplus = '⊕', ominus = '⊖', otimes = '⊗', odot = '⊙', cap = '∩', cup = '∪', vee = '∨', wedge = '∧',
  lor = '∨', land = '∧', setminus = '∖', bmod = 'mod', mod = 'mod',
})
add('rel', {
  leq = '≤', le = '≤', geq = '≥', ge = '≥', neq = '≠', ne = '≠', leqslant = '⩽', geqslant = '⩾', ll = '≪',
  gg = '≫', approx = '≈', equiv = '≡', sim = '∼', simeq = '≃', cong = '≅', propto = '∝', prec = '≺',
  succ = '≻', preceq = '⪯', succeq = '⪰', subset = '⊂', supset = '⊃', subseteq = '⊆', supseteq = '⊇',
  subsetneq = '⊊', ['in'] = '∈', ni = '∋', notin = '∉', mid = '∣', parallel = '∥', perp = '⊥',
  vdash = '⊢', models = '⊨', triangleq = '≜', coloneqq = '≔', therefore = '∴', because = '∵', colon = ':',
  to = '→', rightarrow = '→', gets = '←', leftarrow = '←', Rightarrow = '⇒', Leftarrow = '⇐',
  leftrightarrow = '↔', Leftrightarrow = '⇔', iff = '⟺', implies = '⟹', mapsto = '↦',
  longrightarrow = '⟶', longleftarrow = '⟵', Longrightarrow = '⟹', uparrow = '↑', downarrow = '↓',
  hookrightarrow = '↪', rightleftharpoons = '⇌',
})
add('op', {
  sum = '∑', prod = '∏', int = '∫', iint = '∬', iiint = '∭', oint = '∮', bigcup = '⋃', bigcap = '⋂',
  bigvee = '⋁', bigwedge = '⋀', bigoplus = '⨁', bigotimes = '⨂',
})
add('open', { langle = '⟨', lceil = '⌈', lfloor = '⌊', lvert = '|', lVert = '‖', lbrace = '{', ['{'] = '{' })
add('close', { rangle = '⟩', rceil = '⌉', rfloor = '⌋', rvert = '|', rVert = '‖', rbrace = '}', ['}'] = '}' })
add('space', { quad = '  ', qquad = '    ', [','] = ' ', [':'] = ' ', [';'] = ' ', [' '] = ' ', ['!'] = '' })
for _, f in ipairs({ 'sin', 'cos', 'tan', 'cot', 'sec', 'csc', 'arcsin', 'arccos', 'arctan', 'sinh', 'cosh',
  'tanh', 'log', 'ln', 'lg', 'exp', 'lim', 'liminf', 'limsup', 'max', 'min', 'sup', 'inf', 'det', 'dim',
  'ker', 'arg', 'deg', 'gcd', 'Pr' }) do
  SYM[f] = { f, 'op' }
end

local CHARS = {
  ['+'] = { '+', 'bin' }, ['-'] = { '−', 'bin' }, ['*'] = { '∗', 'bin' }, ['='] = { '=', 'rel' },
  ['<'] = { '<', 'rel' }, ['>'] = { '>', 'rel' }, [':'] = { ':', 'rel' }, [','] = { ',', 'punct' },
  [';'] = { ';', 'punct' }, ['('] = { '(', 'open' }, ['['] = { '[', 'open' }, [')'] = { ')', 'close' },
  [']'] = { ']', 'close' }, ['~'] = { ' ', 'space' },
}

-- character → raised or lowered form
local function scripts(from, to)
  local t = {}
  for i, c in ipairs(vim.fn.split(from, '\\zs')) do t[c] = vim.fn.strcharpart(to, i - 1, 1) end
  return t
end
local SUP = scripts('0123456789+-−=()niabcdefghjklmoprstuvwxyzABDEGHIJKLMNOPRTUVWαβγδθφχι′∘*∗†⊤',
  '⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁻⁼⁽⁾ⁿⁱᵃᵇᶜᵈᵉᶠᵍʰʲᵏˡᵐᵒᵖʳˢᵗᵘᵛʷˣʸᶻᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᴿᵀᵁⱽᵂᵅᵝᵞᵟᶿᵠᵡᶥ′°**†ᵀ')
local SUB = scripts('0123456789+-−=()aehijklmnoprstuvxβγρφχ', '₀₁₂₃₄₅₆₇₈₉₊₋₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓᵦᵧᵨᵩᵪ')

-- "x^{…}": raised characters if Unicode has them all, else "^(…)"
local function script(s, map, mark)
  if s == '' then return '' end
  for c in s:gmatch(CHAR) do
    if not map[c] then return mark .. (s:match('^' .. CHAR .. '$') and s or '(' .. s .. ')') end
  end
  return (s:gsub(CHAR, map))
end

-- styled capitals: code point of "A", and letters that live elsewhere in Unicode
local ALPHABETS = {
  mathbb = { 0x1D538, { C = 'ℂ', H = 'ℍ', N = 'ℕ', P = 'ℙ', Q = 'ℚ', R = 'ℝ', Z = 'ℤ' } },
  mathcal = { 0x1D49C, { B = 'ℬ', E = 'ℰ', F = 'ℱ', H = 'ℋ', I = 'ℐ', L = 'ℒ', M = 'ℳ', R = 'ℛ' } },
}

-- combining marks
local ACCENTS = {
  hat = '\204\130', widehat = '\204\130', tilde = '\204\131', widetilde = '\204\131', bar = '\204\132',
  overline = '\204\133', dot = '\204\135', ddot = '\204\136', vec = '\226\131\151',
}

local TEXT = { text = true, textrm = true, textbf = true, textit = true, mbox = true } -- content is prose
local FONT = { mathrm = true, mathbf = true, mathit = true, mathsf = true, mathtt = true, boldsymbol = true, boxed = true }
local STYLE = { displaystyle = true, textstyle = true, limits = true, nolimits = true }
local SIZED = { left = 'open', right = 'close', middle = 'rel', big = false, Big = false, bigg = false, Bigg = false, bigl = 'open', bigr = 'close', Bigl = 'open', Bigr = 'close' }
local ENVS = { pmatrix = { '(', ')' }, bmatrix = { '[', ']' }, vmatrix = { '|', '|' }, cases = { '{ ', '' } }
-- in these "&" sits before "=", which spaces itself; elsewhere it separates columns
local ALIGNED = { aligned = true, align = true, ['align*'] = true, split = true, gathered = true }

-- { 'cmd', name } | { 'char', c } | { 'space' }
local function tokenize(s)
  local out, i = {}, 1
  while i <= #s do
    local name = s:match('^\\(%a+)', i) or s:match('^\\(' .. CHAR .. ')', i)
    if name and name:match('^%s') then name = ' ' end -- "\" then a line break is a space too
    local ws = s:match('^%s+', i)
    if name then
      out[#out + 1] = { 'cmd', name }
      i = i + 1 + #name
    elseif ws then
      out[#out + 1] = { 'space' }
      i = i + #ws
    else
      local c = s:match('^' .. CHAR, i) or s:sub(i, i) -- a lone "\" at the end is kept as text
      out[#out + 1] = { 'char', c }
      i = i + #c
    end
  end
  return out
end

-- Atoms { text, class } → text, spaced as TeX spaces them; `tight` in scripts.
local function join(atoms, tight)
  local out, prev = {}, nil
  for _, a in ipairs(atoms) do
    local c = a[2]
    -- "−" leading or after an operator is a sign, not a subtraction
    if c == 'bin' and (not prev or prev == 'bin' or prev == 'rel' or prev == 'open' or prev == 'punct' or prev == 'op') then c = 'ord' end
    local gap = c == 'rel' or c == 'bin' or c == 'op' and prev ~= 'open'
      or prev == 'rel' or prev == 'bin' or prev == 'punct' or prev == 'op' and c == 'ord'
    if gap and not tight and prev and prev ~= 'space' and c ~= 'space' and c ~= 'close' and c ~= 'punct' then
      out[#out + 1] = ' '
    end
    out[#out + 1] = a[1]
    prev = c
  end
  return table.concat(out)
end

-- "(a + b)" where "a + b" would read wrongly next to "/" or "√"
local function operand(atoms)
  local s = join(atoms)
  local simple = #atoms <= 1 or s:match('^[%w.]+$')
  return simple and s or '(' .. s .. ')'
end

-- An atom for a whole group: one atom keeps its class ("{=}" is still a relation).
local function group(atoms) return { join(atoms), #atoms == 1 and atoms[1][2] or 'ord' } end

local function convert(tex)
  local tokens, p, amp = tokenize(tex), 1, '  '
  local function peek()
    while tokens[p] and tokens[p][1] == 'space' do p = p + 1 end
    return tokens[p]
  end
  local function take()
    local t = peek()
    p = p + 1
    return t
  end
  local function is(t, c) return t and t[1] == 'char' and t[2] == c end
  -- one token as { text, class }
  local function atom(t)
    if t[1] == 'cmd' then return SYM[t[2]] or { '\\' .. t[2], 'op' } end
    return CHARS[t[2]] or { t[2], 'ord' }
  end
  -- a {group} as written, spaces kept: the name in \begin{…}, the prose in \text{…}
  local function raw()
    local t = take()
    if not t then return '' end
    if not is(t, '{') then return atom(t)[1] end
    local out, depth = {}, 1
    while tokens[p] do
      t, p = tokens[p], p + 1
      depth = depth + (is(t, '{') and 1 or is(t, '}') and -1 or 0)
      if depth == 0 then break end
      if not is(t, '{') and not is(t, '}') then out[#out + 1] = t[1] == 'space' and ' ' or atom(t)[1] end
    end
    return table.concat(out)
  end

  local expr
  local function arg() -- a {group} or a single item
    if is(peek(), '{') then
      take()
      return expr('}')
    end
    return expr(nil, true)
  end
  local function command(v, push)
    if SYM[v] then return push(unpack(SYM[v])) end
    if v == '\\' then return push(';', 'punct') end -- a line break
    if STYLE[v] then return end
    if TEXT[v] then return push(raw()) end
    if FONT[v] then return push(unpack(group(arg()))) end
    if ACCENTS[v] then
      return push((join(arg()):gsub(CHAR, function(c) return c .. ACCENTS[v] end)))
    end
    if ALPHABETS[v] then
      local first, special = unpack(ALPHABETS[v])
      return push((join(arg()):gsub('%u', function(c) return special[c] or vim.fn.nr2char(first + c:byte() - 65) end)))
    end
    if SIZED[v] ~= nil then -- the class it gives its delimiter, or false to keep the delimiter's own
      local d = take()
      if not d or is(d, '.') then return end -- "\left." is an invisible delimiter
      local a = atom(d)
      return push(a[1], SIZED[v] or a[2])
    end
    if v == 'frac' or v == 'dfrac' or v == 'tfrac' then
      local a, b = arg(), arg()
      return push(operand(a) .. '/' .. operand(b))
    end
    if v == 'binom' then
      local a, b = arg(), arg()
      return push('(' .. join(a) .. ' choose ' .. join(b) .. ')')
    end
    if v == 'sqrt' then
      local n
      if is(peek(), '[') then
        take()
        n = join(expr(']'), true)
      end
      local root = n == '3' and '∛' or n == '4' and '∜' or n and script(n, SUP, '^') .. '√' or '√'
      return push(root .. operand(arg()))
    end
    if v == 'operatorname' then
      if is(peek(), '*') then take() end
      return push(raw(), 'op')
    end
    if v == 'color' or v == 'textcolor' then -- the color goes; what it colors stays
      raw()
      return
    end
    if v == 'not' then
      local s = join(arg())
      return push(s == '=' and '≠' or s == '∈' and '∉' or s .. '\204\184', 'rel')
    end
    if v == 'pmod' then return push(' (mod ' .. join(arg()) .. ')', 'space') end
    if v == 'begin' then
      local env, outer = raw(), amp
      if env == 'array' then raw() end -- column spec
      amp = not ALIGNED[env] and '  ' or nil
      local body = join(expr('end'))
      amp = outer
      take()
      raw()
      local wrap = ENVS[env] or { '', '' }
      return push(wrap[1] .. body:gsub('[;%s]+$', '') .. wrap[2])
    end
    push('\\' .. v, 'op')
  end
  -- Atoms up to `stop`: a closing character (consumed), or "end" for \end
  -- (left for \begin). `one`: a single item.
  function expr(stop, one)
    local atoms = {}
    local function push(text, class) atoms[#atoms + 1] = { text, class or 'ord' } end
    local function attach(s) -- scripts and primes belong to the atom before
      if atoms[#atoms] then atoms[#atoms][1] = atoms[#atoms][1] .. s else push(s) end
    end
    while true do
      local t = peek()
      if not t or stop == 'end' and t[1] == 'cmd' and t[2] == 'end' then return atoms end
      take()
      local v = t[2]
      if is(t, stop) then return atoms end
      if t[1] == 'cmd' then
        if v == 'end' then raw() else command(v, push) end -- a stray \end shows nothing
      elseif v == '^' or v == '_' then
        attach(script(join(arg(), true), v == '^' and SUP or SUB, v))
      elseif v == "'" then
        attach('′')
      elseif v == '{' then
        push(unpack(group(expr('}'))))
      elseif v == '&' then
        if amp then push(amp, 'space') end
      elseif v ~= '}' then -- a stray "}" closes nothing
        push(unpack(atom(t)))
      end
      if one then return atoms end
    end
  end

  local atoms = {}
  while peek() do vim.list_extend(atoms, expr('}')) end -- a stray "}" ends expr early; carry on after it
  return join(atoms)
end

-- LaTeX math → one line of Unicode text. Unknown commands show as written;
-- so does the whole formula when it nests too deep for Lua's stack.
function M.text(tex)
  local ok, s = pcall(convert, tex)
  return ok and s or tex
end

local last = {} -- key → last ready picture, shown while an edit re-renders

function M.reset() last = {} end

-- Display math as picture lines. Nil while it renders (unless an earlier
-- version under `key` is ready) or where pictures cannot show; nil, error
-- when KaTeX rejects it.
function M.picture(tex, width, key)
  if not image.supported or image.problem then return nil end
  local state, a, b = browser.math(tex, theme.math)
  if state == 'ready' then
    local lines = media.picture(a, b[1], b[2], width, 2)
    if key then last[key] = lines end
    return lines
  elseif state == 'error' then
    return nil, a
  end
  media.pending = media.pending + 1
  return key and last[key]
end

return M
