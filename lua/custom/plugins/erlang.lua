local function ensure_treesitter_parsers(languages)
  local ok_treesitter, treesitter = pcall(require, 'nvim-treesitter')
  local ok_parsers, parsers = pcall(require, 'nvim-treesitter.parsers')
  if not ok_treesitter or not ok_parsers then
    return
  end

  local installed = {}
  for _, lang in ipairs(treesitter.get_installed 'parsers') do
    installed[lang] = true
  end

  local missing = {}
  for _, lang in ipairs(languages) do
    if parsers[lang] and not installed[lang] then
      missing[#missing + 1] = lang
    end
  end

  if #missing > 0 then
    treesitter.install(missing, { summary = true }):wait(300000)
  end
end

local function lsp_capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  local ok, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
  if ok then
    capabilities = vim.tbl_deep_extend('force', capabilities, cmp_nvim_lsp.default_capabilities())
  end
  return capabilities
end

local function hover_signature_chunks(result)
  if not result or not result.contents then
    return nil
  end

  local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
  lines = vim.lsp.util.trim_empty_lines(lines)
  if not lines or vim.tbl_isempty(lines) then
    return nil
  end

  for _, line in ipairs(lines) do
    line = vim.trim(line)
    if line ~= '' and line ~= '```' and not line:match '^```' then
      return { { line, 'Comment' } }
    end
  end

  return nil
end

local function setup_hover_echo(bufnr, client)
  local function clear_hover()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_echo({ { '' } }, false, {})
    end
  end

  local timer = vim.uv.new_timer()

  local function show_hover()
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    client:request('textDocument/hover', params, function(err, result)
      local chunks = not err and hover_signature_chunks(result) or nil
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        if chunks then
          vim.api.nvim_echo(chunks, false, {})
        else
          clear_hover()
        end
      end)
    end, bufnr)
  end

  local function debounce(delay)
    if not timer then
      return
    end
    timer:stop()
    timer:start(delay, 0, function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          show_hover()
        end
      end)
    end)
  end

  local group = vim.api.nvim_create_augroup('custom-erlang-hover-' .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      debounce(180)
    end,
  })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      debounce(120)
    end,
  })

  vim.api.nvim_create_autocmd({ 'InsertEnter', 'BufLeave' }, {
    group = group,
    buffer = bufnr,
    callback = clear_hover,
  })

  vim.api.nvim_create_autocmd('LspDetach', {
    group = group,
    buffer = bufnr,
    callback = function()
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
      clear_hover()
    end,
  })
end

local function disable_legacy_servers()
  local group = vim.api.nvim_create_augroup('custom-erlang-disable-legacy', { clear = true })

  vim.schedule(function()
    pcall(vim.lsp.enable, 'erlangls', false)
  end)

  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == 'erlangls' then
        vim.schedule(function()
          vim.lsp.stop_client(client.id, true)
        end)
      end
    end,
  })
end

local function enable_elp_features()
  local group = vim.api.nvim_create_augroup('custom-erlang-lsp', { clear = true })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client or client.name ~= 'elp' then
        return
      end

      setup_hover_echo(args.buf, client)

      if client.server_capabilities.inlayHintProvider then
        vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
      end
    end,
  })
end

return {
  {
    'williamboman/mason-lspconfig.nvim',
    optional = true,
    opts = function(_, opts)
      local exclude = { elixirls = true, erlangls = true }
      if opts.automatic_enable == nil or opts.automatic_enable == true then
        opts.automatic_enable = { exclude = { 'elixirls', 'erlangls' } }
      elseif type(opts.automatic_enable) == 'table' then
        opts.automatic_enable.exclude = opts.automatic_enable.exclude or {}
        for _, name in ipairs(opts.automatic_enable.exclude) do
          exclude[name] = true
        end
        opts.automatic_enable.exclude = vim.tbl_keys(exclude)
      end
      return opts
    end,
  },
  {
    'neovim/nvim-lspconfig',
    opts = function(_, opts)
      ensure_treesitter_parsers { 'erlang' }
      disable_legacy_servers()

      vim.lsp.config('elp', {
        capabilities = lsp_capabilities(),
      })
      vim.lsp.enable 'elp'

      enable_elp_features()

      return opts
    end,
  },
}
