return {
  -- Roslyn LSP for C# with Razor support
  {
    'seblj/roslyn.nvim',
    ft = { 'cs', 'csproj', 'sln', 'razor', 'cshtml' },
  },

  -- HTML LSP for Razor completions and formatting
  {
    'neovim/nvim-lspconfig',
    optional = true,
    opts = {
      servers = {
        html = {
          filetypes = { 'html', 'razor', 'cshtml' },
        },
      },
    },
  },

  -- CSharpier formatter
  {
    'stevearc/conform.nvim',
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.cs = { 'csharpier' }
      opts.formatters_by_ft.razor = { 'csharpier' }

      opts.formatters = opts.formatters or {}
      opts.formatters.csharpier = {
        command = 'csharpier',
        args = { '--write-stdout' },
      }

      return opts
    end,
  },

  -- TreeSitter for syntax highlighting
  {
    'nvim-treesitter/nvim-treesitter',
    opts = function(_, opts)
      if type(opts.ensure_installed) == 'table' then
        vim.list_extend(opts.ensure_installed, { 'c_sharp', 'html', 'css' })
      end
      return opts
    end,
  },

  -- Telescope configuration to exclude virtual files
  {
    'nvim-telescope/telescope.nvim',
    optional = true,
    opts = function(_, opts)
      opts.defaults = opts.defaults or {}
      opts.defaults.file_ignore_patterns = opts.defaults.file_ignore_patterns or {}
      table.insert(opts.defaults.file_ignore_patterns, '%__virtual.cs$')
      return opts
    end,
  },

  -- Ensure Mason installs required packages
  {
    'williamboman/mason.nvim',
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { 'roslyn', 'rzls', 'html-lsp', 'csharpier' })
      return opts
    end,
  },
}
