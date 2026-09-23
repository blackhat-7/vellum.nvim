-- Following a link from the preview: URLs open in the browser, "#anchor"
-- jumps to the heading, a markdown file opens in the source window.
local M = {}

local function trim_label(s) return vim.trim(s:lower():gsub('%s+', ' ')) end

-- The destination of reference link `label` in `buf`, or nil.
local function definition(buf, label)
  local root = vim.treesitter.get_parser(buf, 'markdown'):parse()[1]:root()
  local query = vim.treesitter.query.parse('markdown', '(link_reference_definition (link_label) @label (link_destination) @dest)')
  local want, found = trim_label(label)
  for _, match in query:iter_matches(root, buf, 0, -1) do
    local l = vim.treesitter.get_node_text(match[1][1], buf)
    if trim_label(l:sub(2, -2)) == want then found = found or vim.treesitter.get_node_text(match[2][1], buf) end
  end
  return found and (found:match('^<(.*)>$') or found)
end

-- GitHub's heading id: lowercase, punctuation dropped, spaces to dashes.
local function slug(text)
  text = text:gsub('[*_`]', ''):lower():gsub('[%z\1-\127]', function(c) return c:match('[%w%- ]') and c or '' end)
  return (text:gsub(' ', '-'))
end

-- 0-based row of the heading `anchor` points to in `buf`, or nil. Repeated
-- headings get "-1", "-2", … like on GitHub.
local function heading(buf, anchor)
  local root = vim.treesitter.get_parser(buf, 'markdown'):parse()[1]:root()
  local query = vim.treesitter.query.parse('markdown', '[(atx_heading (inline) @text) (setext_heading (paragraph) @text)]')
  local seen = {}
  for _, node in query:iter_captures(root, buf, 0, -1) do
    local s = slug(vim.trim((vim.treesitter.get_node_text(node, buf):gsub('%s*#+%s*$', ''))))
    local id = seen[s] and s .. '-' .. seen[s] or s
    seen[s] = (seen[s] or 0) + 1
    if id == anchor:lower() then return (node:start()) end
  end
end

-- Follow `link` (a destination, or { ref = label }) found in `buf`, shown in
-- window `win`. Returns an error message, or nil.
function M.follow(link, buf, win)
  local target = type(link) == 'table' and definition(buf, link.ref) or link
  if not target or target == '' then return 'link has no destination' end
  if target:match('^%a[%w+.-]*:') then
    vim.ui.open(target)
    return
  end
  local path, anchor = target:match('^([^#]*)#?(.*)$')
  if path ~= '' then
    path = vim.uri_decode(path)
    if path:sub(1, 1) ~= '/' then path = vim.fs.dirname(vim.api.nvim_buf_get_name(buf)) .. '/' .. path end
    path = vim.fs.normalize(path)
    if not vim.uv.fs_stat(path) then return 'no such file: ' .. path end
    if not path:lower():match('%.md$') and not path:lower():match('%.markdown$') then
      vim.ui.open(path)
      return
    end
    local ok, err = pcall(vim.api.nvim_win_call, win, function() vim.cmd.edit(vim.fn.fnameescape(path)) end)
    if not ok then return (tostring(err):gsub('^.-(E%d+:)', '%1')) end
    buf = vim.api.nvim_win_get_buf(win)
  end
  if anchor == '' then return end
  local row = heading(buf, vim.uri_decode(anchor))
  if not row then return 'no heading #' .. anchor end
  vim.api.nvim_win_call(win, function()
    vim.api.nvim_win_set_cursor(win, { row + 1, 0 })
    vim.cmd('normal! zt')
  end)
end

return M
