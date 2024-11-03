return {
  {
    {
      'elixir-tools/elixir-tools.nvim',
      version = '*',
      event = { 'BufReadPre', 'BufNewFile' },
      config = function()
        local elixir = require 'elixir'
        local elixirls = require 'elixir.elixirls'

        elixir.setup {
          nextls = { enable = true },
          elixirls = {
            enable = true,
            settings = elixirls.settings {
              dialyzerEnabled = false,
              enableTestLenses = false,
            },
            on_attach = function(client, bufnr)
              vim.keymap.set('n', '<space>fp', ':ElixirFromPipe<cr>', { buffer = true, noremap = true })
              vim.keymap.set('n', '<space>tp', ':ElixirToPipe<cr>', { buffer = true, noremap = true })
              vim.keymap.set('v', '<space>em', ':ElixirExpandMacro<cr>', { buffer = true, noremap = true })
            end,
          },
          projectionist = {
            enable = true,
          },
        }
      end,
      dependencies = {
        'nvim-lua/plenary.nvim',
      },
    },
    {
      'liquidz/vim-iced', -- Clojure
      dependencies = {
        'guns/vim-sexp',
        -- 'junegunn/fzf',
        'liuchengxu/vim-clap',
      },
    },
    {
      'alaviss/nim.nvim', -- Nim
    },
    {
      'fatih/vim-go', -- Go
      init = function()
        vim.g.go_auto_type_info = 1
      end,
    },
    {
      'jjo/vim-cue', -- Cue
    },
    {
      'ziglang/zig.vim', -- Zig
    },
    {
      'mrcjkb/rustaceanvim', -- Rust
      version = '^4',
      ft = { 'rust' },
      init = function()
        vim.g.rustfmt_autosave = 1
        vim.g.rustaceanvim = {
          tools = {
            autoSetHints = true,
            hoverWithButtons = true,
            inlayHints = {
              chainingHints = true,
              typeHints = true,
              parameterHints = true,
            },
            runnables = {
              useCargo = true,
            },
            debuggables = {
              useLLDB = true,
            },
          },
        }
      end,
    },
    {
      'OmniSharp/omnisharp-vim', -- CSharp
    },
    -- DataScience / Machine Learning / DeepLearning
    {
      'jalvesaq/Nvim-R', -- R
    },
    {
      'JuliaEditorSupport/julia-vim', -- Julia
    },
    {
      'czheo/mojo.vim',
      ft = { 'mojo' },
      init = function()
        vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufRead' }, {
          pattern = { '*.🔥' },
          callback = function()
            if vim.bo.filetype ~= 'mojo' then
              vim.bo.filetype = 'mojo'
            end
          end,
        })

        vim.api.nvim_create_autocmd('FileType', {
          pattern = 'mojo',
          callback = function()
            local modular = vim.env.MODULAR_HOME
            local lsp_cmd = modular .. '/pkg/packages.modular.com_mojo/bin/mojo-lsp-server'

            vim.bo.expandtab = true
            vim.bo.shiftwidth = 4
            vim.bo.softtabstop = 4

            vim.lsp.start {
              name = 'mojo',
              cmd = { lsp_cmd },
            }
          end,
        })
      end,
    },
  },
}
