local function clojure_root_markers(existing)
  local root_markers = {}
  local seen = {}

  local defaults = existing or {
    'project.clj',
    'deps.edn',
    'build.boot',
    'shadow-cljs.edn',
    'bb.edn',
    '.git',
  }

  for _, marker in ipairs(defaults) do
    if not seen[marker] then
      seen[marker] = true
      table.insert(root_markers, marker)
    end
  end

  if not seen['squint.edn'] then
    local git_index = nil

    for index, marker in ipairs(root_markers) do
      if marker == '.git' then
        git_index = index
        break
      end
    end

    if git_index then
      table.insert(root_markers, git_index, 'squint.edn')
    else
      table.insert(root_markers, 'squint.edn')
    end
  end

  return root_markers
end

local function clojure_lsp_settings(existing)
  return vim.tbl_deep_extend('force', {
    ['clojure-lsp'] = {
      ['semantic-tokens?'] = true,
      ['code-lens-segregate-test-references'] = true,
    },
  }, existing or {})
end

local function clojure_lsp_capabilities(existing)
  local capabilities = vim.tbl_deep_extend('force', {}, existing or {})
  local ok, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')

  if ok then
    capabilities = vim.tbl_deep_extend('force', capabilities, cmp_nvim_lsp.default_capabilities())
  end

  return capabilities
end

local function clojure_root_dir(root_markers)
  local root_pattern = require('lspconfig.util').root_pattern(unpack(root_markers))

  return function(bufnr, on_dir)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == '' then
      on_dir(vim.uv.cwd())
      return
    end

    on_dir(root_pattern(name))
  end
end

return {
  {
    'neovim/nvim-lspconfig',
    optional = true,
    init = function()
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('clojure-lsp-codelens', { clear = true }),
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if not client or client.name ~= 'clojure_lsp' or not client.server_capabilities.codeLensProvider then
            return
          end

          vim.lsp.codelens.enable(true, { bufnr = event.buf })
        end,
      })
    end,
    opts = function(_, opts)
      opts.servers = opts.servers or {}

      local server = vim.tbl_deep_extend('force', {}, opts.servers.clojure_lsp or {})
      local root_markers = clojure_root_markers(server.root_markers)

      server.root_markers = root_markers
      server.root_dir = clojure_root_dir(root_markers)
      server.settings = clojure_lsp_settings(server.settings)
      server.capabilities = clojure_lsp_capabilities(server.capabilities)
      server.autostart = false
      opts.servers.clojure_lsp = server

      vim.lsp.config('clojure_lsp', {
        filetypes = { 'clojure', 'edn' },
        root_markers = root_markers,
        root_dir = server.root_dir,
        settings = server.settings,
        capabilities = server.capabilities,
      })
      vim.lsp.enable 'clojure_lsp'

      return opts
    end,
  },
}
