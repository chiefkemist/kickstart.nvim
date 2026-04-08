return {
  {
    'neovim/nvim-lspconfig',
    opts = function(_, opts)
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('unified-clojure-navigation', { clear = true }),
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if not client or client.name ~= 'clojure_lsp' then
            return
          end

          local bufnr = event.buf

          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then
              return
            end

            vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = bufnr, desc = 'Go to definition', silent = true })
            vim.keymap.set('n', 'gr', vim.lsp.buf.references, { buffer = bufnr, desc = 'Find references', silent = true })
            vim.keymap.set('n', '<leader>ld', vim.lsp.buf.definition, { buffer = bufnr, desc = 'LSP: Direct definition', silent = true })
            vim.keymap.set('n', '<leader>lr', vim.lsp.buf.references, { buffer = bufnr, desc = 'LSP: Direct references', silent = true })
            vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = bufnr, desc = 'Hover documentation', silent = true })
            vim.keymap.set('n', 'gI', vim.lsp.buf.implementation, { buffer = bufnr, desc = 'Go to implementation', silent = true })
            vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, { buffer = bufnr, desc = 'Type definition', silent = true })
            vim.keymap.set('n', '<leader>cc', vim.lsp.buf.code_action, { buffer = bufnr, desc = 'Code actions', silent = true })
            vim.keymap.set('n', '<leader>cr', vim.lsp.buf.rename, { buffer = bufnr, desc = 'Rename symbol', silent = true })
            vim.keymap.set('n', '<leader>cf', function()
              vim.lsp.buf.format { async = false }
            end, { buffer = bufnr, desc = 'Format buffer', silent = true })
            vim.keymap.set('n', '<leader>ct', function()
              vim.lsp.buf.execute_command {
                command = 'cycle-coll',
                arguments = { vim.uri_from_bufnr(bufnr) },
              }
            end, { buffer = bufnr, desc = 'Toggle between source/test', silent = true })
            vim.keymap.set('n', '<leader>cR', function()
              vim.lsp.buf.execute_command {
                command = 'find-references',
                arguments = { vim.uri_from_bufnr(bufnr), vim.fn.line '.' - 1, vim.fn.col '.' - 1 },
              }
            end, { buffer = bufnr, desc = 'Find all references (including re-frame)', silent = true })
          end)
        end,
      })

      return opts
    end,
  },
}
