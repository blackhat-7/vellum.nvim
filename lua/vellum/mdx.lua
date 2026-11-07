-- MDX is markdown plus JSX. The JSX tags already render like HTML; the two
-- MDX-only constructs that are not content are hidden here: `import`/`export`
-- statements (code that wires up components) and `{/* comments */}`.
local M = {}

local function filetypes(buf) return vim.split(vim.bo[buf].filetype, '.', { plain = true }) end

-- MDX by filetype or name: Neovim does not detect .mdx, so without a plugin
-- that sets one the filetype is empty. A dotted filetype ("markdown.mdx") is
-- several filetypes.
function M.is(buf)
  return vim.api.nvim_buf_get_name(buf):lower():match('%.mdx$') ~= nil or vim.list_contains(filetypes(buf), 'mdx')
end

-- Markdown or MDX: what the preview follows and export takes.
function M.markdown(buf) return vim.list_contains(filetypes(buf), 'markdown') or M.is(buf) end

-- Whether `node`, a block of the document or of a heading's section, is an
-- MDX statement or comment. MDX allows both only there, and markdown parses
-- them as paragraphs. Runs per top-level block on every keystroke, so the
-- first line is checked before the block's text is joined.
function M.hidden(node, lines)
  if node:type() ~= 'paragraph' then return false end
  local sr, _, er, ec = node:range()
  local first = lines[sr + 1] or ''
  if first:match('^import[%s{*]') or first:match('^export%s') then return true end
  if not first:match('^%s*{/%*') then return false end
  if ec == 0 then er = er - 1 end
  return vim.trim(table.concat(lines, '\n', sr + 1, er + 1)):match('^{/%*.*%*/}$') ~= nil
end

-- The lines of `buf`, with MDX statements and comments blanked, for export.
-- Blanking rather than removing keeps the rows of everything else.
function M.lines(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if not M.is(buf) then return lines end
  local function walk(node)
    for n in node:iter_children() do
      if n:type() == 'section' then
        walk(n)
      elseif M.hidden(n, lines) then
        local sr, _, er, ec = n:range()
        if ec == 0 then er = er - 1 end
        for r = sr + 1, er + 1 do lines[r] = '' end
      end
    end
  end
  walk(vim.treesitter.get_parser(buf, 'markdown'):parse()[1]:root())
  return lines
end

return M
