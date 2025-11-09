return {
  -- Roslyn LSP for C# with Razor support
  {
    'seblj/roslyn.nvim',
    ft = { 'cs', 'csproj', 'sln', 'razor', 'cshtml' },
    dependencies = {
      {
        'tris203/rzls.nvim',
        config = true,
      },
    },
    config = function()
      -- Set up .NET environment
      local home = vim.env.HOME
      local dotnet_bin = home .. '/.local/bin'
      local dotnet_root = home .. '/.dotnet'
      
      if not vim.env.PATH:find(dotnet_bin, 1, true) then
        vim.env.PATH = dotnet_bin .. ':' .. vim.env.PATH
      end
      
      vim.env.DOTNET_ROOT = dotnet_root
      vim.env.DOTNET_ROOT_ARM64 = dotnet_root
      
      -- Check if rzls is installed
      local registry_ok, mason_registry = pcall(require, 'mason-registry')
      local cmd = { 'roslyn' }
      
      if registry_ok and mason_registry.is_installed('rzls') then
        local rzls_path = vim.fn.expand('$MASON/packages/rzls/libexec')
        
        if vim.fn.isdirectory(rzls_path) == 1 then
          cmd = {
            'roslyn',
            '--stdio',
            '--logLevel=Information',
            '--extensionLogDirectory=' .. vim.fs.dirname(vim.lsp.get_log_path()),
            '--razorSourceGenerator=' .. vim.fs.joinpath(rzls_path, 'Microsoft.CodeAnalysis.Razor.Compiler.dll'),
            '--razorDesignTimePath=' .. vim.fs.joinpath(rzls_path, 'Targets', 'Microsoft.NET.Sdk.Razor.DesignTime.targets'),
            '--extension',
            vim.fs.joinpath(rzls_path, 'RazorExtension', 'Microsoft.VisualStudioCode.RazorExtension.dll'),
          }
        end
      end
      
      -- Configure using vim.lsp.config as per rzls documentation
      vim.lsp.config('roslyn', {
        cmd = cmd,
        handlers = registry_ok and mason_registry.is_installed('rzls') and require('rzls.roslyn_handlers') or nil,
        on_attach = function(client, bufnr)
          if client.server_capabilities.inlayHintProvider then
            vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
          end
        end,
        capabilities = require('cmp_nvim_lsp').default_capabilities(),
        settings = {
          ['csharp|inlay_hints'] = {
            csharp_enable_inlay_hints_for_implicit_object_creation = true,
            csharp_enable_inlay_hints_for_implicit_variable_types = true,
            csharp_enable_inlay_hints_for_lambda_parameter_types = true,
            csharp_enable_inlay_hints_for_types = true,
            dotnet_enable_inlay_hints_for_indexer_parameters = true,
            dotnet_enable_inlay_hints_for_literal_parameters = true,
            dotnet_enable_inlay_hints_for_object_creation_parameters = true,
            dotnet_enable_inlay_hints_for_other_parameters = true,
            dotnet_enable_inlay_hints_for_parameters = true,
            dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,
            dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
            dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
          },
          ['csharp|code_lens'] = {
            dotnet_enable_references_code_lens = true,
          },
        },
      })
      
      vim.lsp.enable('roslyn')
    end,
    init = function()
      -- Register Razor filetypes before plugin loads
      vim.filetype.add({
        extension = {
          razor = 'razor',
          cshtml = 'razor',
        },
      })
    end,
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
