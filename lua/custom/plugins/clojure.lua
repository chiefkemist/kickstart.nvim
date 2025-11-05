return {
  -- Remove vim-iced as we'll use Conjure for better REPL support
  { 'liquidz/vim-iced', enabled = false },
  
  -- Conjure for interactive REPL-driven development
  {
    'Olical/conjure',
    ft = { 'clojure', 'fennel', 'janet' },
    lazy = true,
    init = function()
      -- Set localleader for Conjure mappings
      vim.g['conjure#mapping#doc_word'] = false
      vim.g['conjure#client#clojure#nrepl#eval#auto_require'] = false
      vim.g['conjure#client#clojure#nrepl#connection#auto_repl#enabled'] = false
    end,
    dependencies = {
      {
        'PaterJason/cmp-conjure',
        config = function()
          local cmp = require('cmp')
          local config = cmp.get_config()
          table.insert(config.sources, {
            name = 'buffer',
            option = {
              sources = {
                { name = 'conjure' },
              },
            },
          })
          cmp.setup(config)
        end,
      },
    },
  },

  -- Better highlighting for Clojure
  {
    'guns/vim-clojure-highlight',
    ft = 'clojure',
  },

  -- S-expression editing - essential for Lisp languages
  {
    'guns/vim-sexp',
    ft = { 'clojure', 'scheme', 'lisp', 'fennel' },
    dependencies = {
      {
        'tpope/vim-sexp-mappings-for-regular-people',
        ft = { 'clojure', 'scheme', 'lisp', 'fennel' },
      },
    },
  },

  -- Additional tools for Clojure development
  {
    'tpope/vim-dispatch',
    cmd = { 'Dispatch', 'Make', 'Focus', 'Start' },
  },

  {
    'clojure-vim/vim-jack-in',
    dependencies = { 'tpope/vim-dispatch' },
    ft = 'clojure',
  },

  -- Note: clojure-lsp is configured in init.lua's servers table

  -- TreeSitter for better syntax highlighting
  {
    'nvim-treesitter/nvim-treesitter',
    opts = function(_, opts)
      if type(opts.ensure_installed) == 'table' then
        vim.list_extend(opts.ensure_installed, { 'clojure' })
      end
      return opts
    end,
  },

  -- Auto-pairs that work well with Clojure
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = function()
      require('nvim-autopairs').setup({
        enable_check_bracket_line = false,
      })
    end,
  },

  -- Rainbow parentheses for better visibility
  {
    'HiPhish/rainbow-delimiters.nvim',
    dependencies = 'nvim-treesitter/nvim-treesitter',
    event = 'VeryLazy',
    main = 'rainbow-delimiters.setup',
    opts = {
      highlight = {
        'RainbowDelimiterRed',
        'RainbowDelimiterYellow',
        'RainbowDelimiterBlue',
        'RainbowDelimiterOrange',
        'RainbowDelimiterGreen',
        'RainbowDelimiterViolet',
        'RainbowDelimiterCyan',
      },
    },
  },
}
