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

-- The file an Obsidian [[note#heading]] points to, as a destination, or nil.
-- A note is found next to `buf`, else anywhere under the vault (the folder
-- holding .obsidian, or `buf`'s folder); "#heading" is the heading's text.
local function wiki(buf, note)
  local name, heading_text = note:match('^([^#]*)#?(.*)$')
  local anchor = heading_text ~= '' and '#' .. slug(heading_text) or ''
  if name == '' then return anchor end
  if not name:lower():match('%.%w+$') then name = name .. '.md' end
  local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
  if vim.uv.fs_stat(dir .. '/' .. name) then return dir .. '/' .. name .. anchor end
  local found = vim.fs.find(function(n, path) return n == vim.fs.basename(name) and (path .. '/' .. n):sub(-#name - 1) == '/' .. name end,
    { path = vim.fs.root(buf, '.obsidian') or dir, type = 'file', limit = 1 })[1]
  return found and found .. anchor
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

-- Follow `link` (a destination, { ref = label } or { wiki = note }) found in
-- `buf`, shown in window `win`. Returns an error message, or nil.
function M.follow(link, buf, win)
  local target = link
  if type(link) == 'table' then
    target = link.ref and definition(buf, link.ref) or link.wiki and wiki(buf, link.wiki)
    if not target then return link.wiki and 'no note named ' .. link.wiki or 'no definition for [' .. link.ref .. ']' end
  end
  if target == '' then return 'link has no destination' end
  if target:match('^%a[%w+.-]*:') then return select(2, vim.ui.open(target)) end
  local path, anchor = target:match('^([^#]*)#?(.*)$')
  if path ~= '' then
    path = vim.uri_decode(path)
    if path:sub(1, 1) ~= '/' then path = vim.fs.dirname(vim.api.nvim_buf_get_name(buf)) .. '/' .. path end
    path = vim.fs.normalize(path)
    if not vim.uv.fs_stat(path) then return 'no such file: ' .. path end
    if not path:lower():match('%.md$') and not path:lower():match('%.markdown$') then return select(2, vim.ui.open(path)) end
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
