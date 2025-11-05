-- Unified Clojure navigation configuration
-- This ensures consistent behavior for both local and external symbols

return {
  {
    'neovim/nvim-lspconfig',
    opts = function(_, opts)
      -- Store original telescope mappings
      local telescope_builtin = nil
      
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('unified-clojure-navigation', { clear = true }),
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.name == 'clojure_lsp' then
            local bufnr = event.buf
            
            -- Load telescope only when needed
            local function get_telescope()
              if not telescope_builtin then
                telescope_builtin = require('telescope.builtin')
              end
              return telescope_builtin
            end
            
            -- Smart go-to-definition that handles both cases
            local function smart_goto_definition()
              -- First try regular LSP definition
              local params = vim.lsp.util.make_position_params()
              local result = vim.lsp.buf_request_sync(bufnr, 'textDocument/definition', params, 1000)
              
              if result and next(result) then
                -- Check if we got results
                for _, res in pairs(result) do
                  if res.result and #res.result > 0 then
                    -- If multiple results, use telescope
                    if #res.result > 1 then
                      get_telescope().lsp_definitions()
                    else
                      -- Single result, use standard jump
                      vim.lsp.buf.definition()
                    end
                    return
                  end
                end
              end
              
              -- Fallback to telescope if no results (might find in jars)
              get_telescope().lsp_definitions()
            end
            
            -- Smart references that always uses telescope for better UI
            local function smart_references()
              get_telescope().lsp_references()
            end
            
            -- Override the problematic mappings with smart versions
            vim.keymap.set('n', 'gd', smart_goto_definition, 
              { buffer = bufnr, desc = 'Go to definition (smart)', silent = true })
            
            vim.keymap.set('n', 'gr', smart_references, 
              { buffer = bufnr, desc = 'Find references', silent = true })
            
            -- Keep standard mappings as fallbacks
            vim.keymap.set('n', '<leader>ld', vim.lsp.buf.definition, 
              { buffer = bufnr, desc = 'LSP: Direct definition', silent = true })
            
            vim.keymap.set('n', '<leader>lr', vim.lsp.buf.references, 
              { buffer = bufnr, desc = 'LSP: Direct references', silent = true })
            
            -- Additional useful mappings for Clojure
            vim.keymap.set('n', 'K', vim.lsp.buf.hover, 
              { buffer = bufnr, desc = 'Hover documentation', silent = true })
            
            vim.keymap.set('n', 'gI', vim.lsp.buf.implementation, 
              { buffer = bufnr, desc = 'Go to implementation', silent = true })
            
            vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, 
              { buffer = bufnr, desc = 'Type definition', silent = true })
            
            -- Clojure-specific commands
            vim.keymap.set('n', '<leader>cc', vim.lsp.buf.code_action, 
              { buffer = bufnr, desc = 'Code actions', silent = true })
            
            vim.keymap.set('n', '<leader>cr', vim.lsp.buf.rename, 
              { buffer = bufnr, desc = 'Rename symbol', silent = true })
            
            vim.keymap.set('n', '<leader>cf', function()
              vim.lsp.buf.format({ async = false })
            end, { buffer = bufnr, desc = 'Format buffer', silent = true })
            
            -- Jump between source and test
            vim.keymap.set('n', '<leader>ct', function()
              vim.lsp.buf.execute_command({
                command = 'cycle-coll',
                arguments = { vim.uri_from_bufnr(bufnr) }
              })
            end, { buffer = bufnr, desc = 'Toggle between source/test', silent = true })
            
            -- Find all references in project (including re-frame subscriptions, etc)
            vim.keymap.set('n', '<leader>cR', function()
              vim.lsp.buf.execute_command({
                command = 'find-references',
                arguments = { vim.uri_from_bufnr(bufnr), vim.fn.line('.') - 1, vim.fn.col('.') - 1 }
              })
            end, { buffer = bufnr, desc = 'Find all references (including re-frame)', silent = true })
          end
        end,
      })
      
      return opts
    end,
  },
  
  -- Enhance telescope preview for Clojure files
  {
    'nvim-telescope/telescope.nvim',
    opts = function(_, opts)
      opts.pickers = opts.pickers or {}
      opts.pickers.lsp_definitions = {
        jump_type = "never", -- Don't jump immediately, show preview
        show_line = true,
      }
      opts.pickers.lsp_references = {
        jump_type = "never",
        show_line = true,
        include_declaration = false, -- Don't include the definition in references
      }
      return opts
    end,
  },
}