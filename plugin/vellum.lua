vim.api.nvim_create_user_command('Vellum', function(o)
  local sub, arg = o.args:match('^(%S*)%s*(.-)%s*$')
  if sub == '' then
    require('vellum').toggle()
  elseif sub == 'export' then
    require('vellum').export(arg)
  elseif sub == 'build' then
    require('vellum.build').run()
  else
    vim.notify('vellum: unknown command "' .. sub .. '". Use :Vellum, :Vellum build or :Vellum export [file.pdf|file.html]', vim.log.levels.ERROR)
  end
end, {
  nargs = '*',
  desc = 'Toggle the markdown preview, build the renderer, or export: :Vellum [build|export file.pdf|file.html]',
  complete = function(arg, line)
    if line:match('^%S+%s+export%s') then return vim.fn.getcompletion(arg, 'file') end
    return vim.tbl_filter(function(c) return c:find(arg, 1, true) == 1 end, { 'build', 'export' })
  end,
})
