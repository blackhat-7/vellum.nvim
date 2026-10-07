-- MDX is markdown plus JSX. The JSX tags already render like HTML; the two
-- MDX-only constructs that are not content are hidden here: `import`/`export`
-- statements (code that wires up components) and `{/* comments */}`.
local M = {}

local function filetypes(buf) return vim.split(vim.bo[buf].filetype, '.', { plain = true }) end

-- Markdown or MDX by filetype. A dotted filetype ("markdown.mdx") is several.
function M.markdown(buf)
  local fts = filetypes(buf)
  return vim.list_contains(fts, 'markdown') or vim.list_contains(fts, 'mdx')
end

-- The lines of `buf`, with MDX statements and comments blanked in an .mdx
-- buffer. Blanking keeps every row where it was, so scroll sync still maps
-- source rows to preview rows. The second result says whether any changed.
function M.lines(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Neovim does not detect .mdx, so the name counts as well as the filetype
  if not (vim.api.nvim_buf_get_name(buf):lower():match('%.mdx$') or vim.list_contains(filetypes(buf), 'mdx')) then
    return lines, false
  end
  local changed = false
  -- MDX allows both only as top-level blocks, which markdown parses as
  -- paragraphs of the document or of a heading's section
  local function walk(node)
    for n in node:iter_children() do
      if n:type() == 'section' then
        walk(n)
      elseif n:type() == 'paragraph' then
        local sr, _, er, ec = n:range()
        if ec == 0 then er = er - 1 end
        local text = table.concat(lines, '\n', sr + 1, er + 1)
        if text:match('^import[%s{*]') or text:match('^export%s') or vim.trim(text):match('^{/%*.*%*/}$') then
          for r = sr + 1, er + 1 do lines[r] = '' end
          changed = true
        end
      end
    end
  end
  walk(vim.treesitter.get_parser(buf, 'markdown'):parse()[1]:root())
  return lines, changed
end

return M
