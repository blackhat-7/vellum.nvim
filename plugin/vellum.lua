vim.api.nvim_create_user_command('Vellum', function() require('vellum').toggle() end, { desc = 'Toggle the markdown preview' })
