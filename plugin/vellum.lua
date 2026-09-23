vim.api.nvim_create_user_command('Vellum', function(o)
  local sub, arg = o.args:match('^(%S*)%s*(.-)%s*$')
  if sub == '' then
    require('vellum').toggle()
  elseif sub == 'export' then
    require('vellum').export(arg)
  else
    vim.notify('vellum: unknown command "' .. sub .. '". Use :Vellum or :Vellum export [file.pdf|file.html]', vim.log.levels.ERROR)
  end
end, {
  nargs = '*',
  desc = 'Toggle the markdown preview, or export: :Vellum export [file.pdf|file.html]',
  complete = function(arg, line)
    if line:match('^%S+%s+export%s') then return vim.fn.getcompletion(arg, 'file') end
    return vim.tbl_filter(function(c) return c:find(arg, 1, true) == 1 end, { 'export' })
  end,
})
