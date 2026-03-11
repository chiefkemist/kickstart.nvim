local nim_filetypes = { 'nim', 'nims', 'nimble' }

local function is_nim_buffer(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr) and vim.tbl_contains(nim_filetypes, vim.bo[bufnr].filetype)
end

local function get_nim_paths()
  local nimsuggest = vim.fn.expand '~/.nimble/bin/nimsuggest'
  local nim_bin = vim.fn.exepath 'nim'
  if nim_bin == '' then
    nim_bin = vim.fn.expand '~/.nimble/bin/nim'
  end

  local nimble_bin = vim.fn.expand '~/.nimble/bin'
  local choosenim_bin = vim.fn.fnamemodify(vim.fn.resolve(nimsuggest), ':h')

  return {
    nim = nim_bin,
    nimsuggest = nimsuggest,
    nimlangserver = vim.fn.stdpath 'data' .. '/mason/packages/nimlangserver/nimlangserver',
    path = table.concat({ nimble_bin, choosenim_bin, vim.env.PATH or '' }, ':'),
  }
end

local function get_nim_capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  local ok_cmp, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
  if ok_cmp then
    capabilities = vim.tbl_deep_extend('force', capabilities, cmp_nvim_lsp.default_capabilities())
  end
  return capabilities
end

local function render_signature(signature, active_parameter)
  if not signature or not signature.label then
    return { { '' } }
  end

  local label = signature.label
  local parameter = signature.parameters and signature.parameters[active_parameter]
  if not parameter or not parameter.label then
    return { { label, 'Comment' } }
  end

  local start_col, end_col
  if type(parameter.label) == 'table' then
    start_col = parameter.label[1] + 1
    end_col = parameter.label[2]
  else
    local text = vim.pesc(parameter.label)
    local from, to = label:find(text, 1)
    if from and to then
      start_col = from
      end_col = to
    end
  end

  if not start_col or not end_col then
    return { { label, 'Comment' } }
  end

  return {
    { label:sub(1, start_col - 1), 'Comment' },
    { label:sub(start_col, end_col), 'IncSearch' },
    { label:sub(end_col + 1), 'Comment' },
  }
end

local function hover_signature_chunks(result)
  if not result or not result.contents or not result.contents[1] or not result.contents[1].value then
    return nil
  end

  local value = result.contents[1].value:gsub('\n.*', '')
  if value == '' then
    return nil
  end

  return { { value, 'Comment' } }
end

local function parse_nim_check(output)
  local diagnostics = {}
  local current = nil

  for line in output:gmatch('[^\r\n]+') do
    if not line:match '^Hint: used config file' and not line:match '^%.+$' and line ~= '' then
      local file, lnum, col, severity, message = line:match '^(.-)%((%d+),%s*(%d+)%)%s*(%w+):%s*(.*)$'

      if file and lnum and col and severity and message then
        current = {
          lnum = tonumber(lnum) - 1,
          col = tonumber(col) - 1,
          severity = severity == 'Warning' and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR,
          source = 'nim check',
          message = message,
        }
        diagnostics[#diagnostics + 1] = current
      elseif current then
        current.message = current.message .. '\n' .. line
      end
    end
  end

  return diagnostics
end

local function setup_nim_server(paths)
  if vim.fn.filereadable(paths.nimlangserver) ~= 1 or vim.fn.filereadable(paths.nimsuggest) ~= 1 then
    return
  end

  vim.lsp.config('nim_langserver', {
    capabilities = get_nim_capabilities(),
    cmd = {
      'env',
      'PATH=' .. paths.path,
      paths.nimlangserver,
    },
    filetypes = vim.deepcopy(nim_filetypes),
    root_markers = { '*.nimble', '.git' },
    settings = {
      nim = {
        nimsuggestPath = paths.nimsuggest,
        useNimCheck = false,
        autoCheckFile = true,
        checkOnSave = true,
        formatOnSave = vim.fn.executable 'nph' == 1,
        inlayHints = {
          typeHints = { enable = true },
          exceptionHints = { enable = true },
          parameterHints = { enable = false },
        },
      },
    },
  })

  vim.lsp.enable 'nim_langserver'
end

local function setup_nim_signature_help(bufnr, client)
  local function clear_signature_help()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_echo({ { '' } }, false, {})
    end
  end

  local sig_timer = vim.uv.new_timer()
  local show_signature_help

  local function show_chunks(chunks)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_echo(chunks, false, {})
      end
    end)
  end

  local function get_cursor_context()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''
    local idx = math.min(col, #line)

    while idx > 0 and not line:sub(idx, idx):match('[%w_]') do
      idx = idx - 1
    end

    while idx > 0 and line:sub(idx, idx):match('[%w_]') do
      idx = idx - 1
    end

    local ident_start = idx + 1
    if line:sub(ident_start, ident_start) == '' then
      return nil
    end

    local ident_end = ident_start
    while ident_end < #line and line:sub(ident_end + 1, ident_end + 1):match('[%w_]') do
      ident_end = ident_end + 1
    end

    local suffix = line:sub(ident_end + 1)
    local in_args = line:sub(1, col):find('%([^()]*$') ~= nil

    return {
      position = { line = row - 1, character = ident_start - 1 },
      line = line,
      col = col,
      in_args = in_args,
      has_call_suffix = suffix:match '^%s*%(' ~= nil,
    }
  end

  local function show_hover_signature(opts)
    local context = get_cursor_context()
    if not context then
      if opts and opts.silent then
        clear_signature_help()
      end
      return
    end

    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    params.position = context.position

    client:request('textDocument/hover', params, function(err, result)
      local chunks = not err and hover_signature_chunks(result) or nil
      if chunks then
        show_chunks(chunks)
      elseif opts and opts.silent then
        clear_signature_help()
      else
        show_chunks({ { 'No signature help available', 'Comment' } })
      end
    end)
  end

  local function debounce_signature_help(opts, delay)
    if not sig_timer then
      return
    end

    sig_timer:stop()
    sig_timer:start(delay or 200, 0, function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          if opts and opts.prefer_hover then
            show_hover_signature(opts)
          else
            show_signature_help(opts)
          end
        end
      end)
    end)
  end

  show_signature_help = function(opts)
    opts = opts or {}
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    client:request('textDocument/signatureHelp', params, function(err, result)
      if err or not result or not result.signatures or vim.tbl_isempty(result.signatures) then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            if opts.silent then
              clear_signature_help()
            else
              vim.api.nvim_echo({ { 'No signature help available', 'Comment' } }, false, {})
            end
          end
        end)
        return
      end

      local active = (result.activeSignature or 0) + 1
      local signature = result.signatures[active] or result.signatures[1]
      if not signature or not signature.label then
        return
      end

      local active_parameter = (result.activeParameter or signature.activeParameter or 0) + 1
      local chunks = render_signature(signature, active_parameter)
      show_chunks(chunks)
    end)
  end

  vim.bo[bufnr].omnifunc = 'v:lua.vim.lsp.omnifunc'
  vim.keymap.set('n', 'gK', show_signature_help, { buffer = bufnr, desc = 'LSP: Signature Help' })
  vim.keymap.set('i', '<C-k>', show_signature_help, { buffer = bufnr, desc = 'LSP: Signature Help' })

  vim.api.nvim_create_autocmd('TextChangedI', {
    buffer = bufnr,
    callback = function()
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''
      local prev_char = col > 0 and line:sub(col, col) or ''
      if prev_char == ')' then
        clear_signature_help()
        return
      end
      if prev_char == '(' then
        show_hover_signature { silent = true }
        return
      end
      if prev_char ~= ',' then
        return
      end
      show_signature_help { silent = true }
    end,
  })

  vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
    buffer = bufnr,
    callback = function()
      local context = get_cursor_context()
      if not context then
        clear_signature_help()
        return
      end

      if context.has_call_suffix then
        debounce_signature_help({ silent = true, prefer_hover = true }, 180)
        return
      end

      if context.in_args then
        debounce_signature_help({ silent = true }, 180)
        return
      end

      clear_signature_help()
    end,
  })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    buffer = bufnr,
    callback = function()
      local context = get_cursor_context()
      if not context then
        clear_signature_help()
        return
      end

      if context.has_call_suffix then
        debounce_signature_help({ silent = true, prefer_hover = true }, 120)
        return
      end

      if context.in_args then
        debounce_signature_help({ silent = true }, 120)
        return
      end

      clear_signature_help()
    end,
  })

  vim.api.nvim_create_autocmd('InsertLeave', {
    buffer = bufnr,
    callback = function()
      if sig_timer then
        sig_timer:stop()
      end
      clear_signature_help()
    end,
  })

  vim.api.nvim_create_autocmd('LspDetach', {
    buffer = bufnr,
    callback = function()
      if sig_timer then
        sig_timer:stop()
        sig_timer:close()
        sig_timer = nil
      end
    end,
  })
end

local function setup_nim_attach()
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('nim-lsp-local', { clear = true }),
    callback = function(event)
      local bufnr = event.buf
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if not client or client.name ~= 'nim_langserver' then
        return
      end

      setup_nim_signature_help(bufnr, client)

      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = bufnr, desc = 'Nim: Goto Definition' })
      vim.keymap.set('n', 'gr', vim.lsp.buf.references, { buffer = bufnr, desc = 'Nim: Goto References' })
      vim.keymap.set('n', 'gI', vim.lsp.buf.implementation, { buffer = bufnr, desc = 'Nim: Goto Implementation' })
      vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, { buffer = bufnr, desc = 'Nim: Type Definition' })
      vim.keymap.set('n', '<leader>nb', '<cmd>NimBuild<cr>', { buffer = bufnr, desc = 'Nim: Build' })
      vim.keymap.set('n', '<leader>nr', '<cmd>NimRun<cr>', { buffer = bufnr, desc = 'Nim: Run' })
      vim.keymap.set('n', '<leader>nc', '<cmd>NimCheck<cr>', { buffer = bufnr, desc = 'Nim: Check' })
      vim.keymap.set('n', '<leader>nt', '<cmd>NimTest<cr>', { buffer = bufnr, desc = 'Nim: Test' })

      if client.server_capabilities.inlayHintProvider then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
      end
    end,
  })
end

local function setup_nim_diagnostics(paths)
  local nim_diag_ns = vim.api.nvim_create_namespace 'nim-check-fallback'

  local function run_nim_check(bufnr)
    if not is_nim_buffer(bufnr) then
      return
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == '' then
      return
    end

    local root = nil
    for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr, name = 'nim_langserver' }) do
      root = client.config.root_dir
      if root then
        break
      end
    end
    root = root or vim.fs.dirname(name)

    vim.system({ paths.nim, 'check', '--listFullPaths', name }, { cwd = root, text = true }, function(obj)
      local output = ((obj.stderr or '') .. '\n' .. (obj.stdout or ''))
      local diagnostics = parse_nim_check(output)

      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.diagnostic.set(nim_diag_ns, bufnr, diagnostics)
        end
      end)
    end)
  end

  vim.api.nvim_create_autocmd({ 'BufWritePost', 'InsertLeave' }, {
    group = vim.api.nvim_create_augroup('nim-check-fallback', { clear = true }),
    pattern = { '*.nim', '*.nims', '*.nimble' },
    callback = function(args)
      run_nim_check(args.buf)
    end,
  })
end

local function get_nim_project(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return nil
  end

  local start = vim.fs.dirname(name)
  local nimble = vim.fs.find(function(path)
    return path:match '%.nimble$' ~= nil
  end, { upward = true, path = start })[1]

  if nimble then
    return {
      root = vim.fs.dirname(nimble),
      nimble = nimble,
      file = name,
    }
  end

  return {
    root = start,
    nimble = nil,
    file = name,
  }
end

local function open_nim_terminal(cmd, cwd)
  local escaped = vim.fn.fnameescape(cwd)
  vim.cmd('botright 12split')
  vim.cmd('terminal')
  local job_id = vim.b.terminal_job_id
  if job_id then
    vim.fn.chansend(job_id, 'clear\r')
    vim.fn.chansend(job_id, 'cd ' .. vim.fn.shellescape(cwd) .. ' && ' .. cmd .. '\r')
  else
    vim.cmd('lcd ' .. escaped)
  end
  vim.cmd 'startinsert'
end

local function setup_nim_commands(paths)
  local valid_backends = {
    c = true,
    cpp = true,
    objc = true,
    js = true,
  }

  local function backend_complete(arg_lead)
    local items = { 'c', 'cpp', 'objc', 'js' }
    return vim.tbl_filter(function(item)
      return item:find('^' .. vim.pesc(arg_lead)) ~= nil
    end, items)
  end

  local function current_project()
    local project = get_nim_project(0)
    if not project then
      vim.notify('No current Nim file', vim.log.levels.WARN)
      return nil
    end
    return project
  end

  local function normalize_backend(arg)
    local backend = arg ~= '' and arg or 'c'
    if not valid_backends[backend] then
      vim.notify('Unsupported Nim backend: ' .. backend, vim.log.levels.ERROR)
      return nil
    end
    return backend
  end

  local function define(name, desc, fn)
    vim.api.nvim_create_user_command(name, fn, {
      desc = desc,
      nargs = '?',
      complete = function(_, arg_lead)
        return backend_complete(arg_lead)
      end,
    })
  end

  define('NimBuild', 'Build Nim project or current file; optional backend', function(opts)
    local project = current_project()
    if not project then
      return
    end

    local backend = normalize_backend(opts.args)
    if not backend then
      return
    end

    if project.nimble then
      open_nim_terminal('nimble build --backend:' .. backend, project.root)
    else
      open_nim_terminal(vim.fn.shellescape(paths.nim) .. ' ' .. backend .. ' ' .. vim.fn.shellescape(project.file), project.root)
    end
  end)

  define('NimRun', 'Run Nim project or current file; optional backend', function(opts)
    local project = current_project()
    if not project then
      return
    end

    local backend = normalize_backend(opts.args)
    if not backend then
      return
    end

    if project.nimble then
      open_nim_terminal('nimble run --backend:' .. backend, project.root)
    else
      open_nim_terminal(vim.fn.shellescape(paths.nim) .. ' ' .. backend .. ' -r ' .. vim.fn.shellescape(project.file), project.root)
    end
  end)

  define('NimCheck', 'Check current Nim file; optional backend', function(opts)
    local project = current_project()
    if not project then
      return
    end

    local backend = normalize_backend(opts.args)
    if not backend then
      return
    end

    open_nim_terminal(vim.fn.shellescape(paths.nim) .. ' check --backend:' .. backend .. ' ' .. vim.fn.shellescape(project.file), project.root)
  end)

  define('NimTest', 'Run Nim project tests; optional backend', function(opts)
    local project = current_project()
    if not project then
      return
    end

    local backend = normalize_backend(opts.args)
    if not backend then
      return
    end

    if project.nimble then
      open_nim_terminal('nimble test --backend:' .. backend, project.root)
    else
      vim.notify('NimTest requires a .nimble project', vim.log.levels.WARN)
    end
  end)

  define('NimbleBuild', 'Run nimble build; optional backend', function(opts)
    local project = current_project()
    local backend = normalize_backend(opts.args)
    if not backend then
      return
    end
    if project and project.nimble then
      open_nim_terminal('nimble build --backend:' .. backend, project.root)
    else
      vim.notify('No .nimble project found', vim.log.levels.WARN)
    end
  end)

  define('NimbleRun', 'Run nimble run; optional backend', function(opts)
    local project = current_project()
    local backend = normalize_backend(opts.args)
    if not backend then
      return
    end
    if project and project.nimble then
      open_nim_terminal('nimble run --backend:' .. backend, project.root)
    else
      vim.notify('No .nimble project found', vim.log.levels.WARN)
    end
  end)

  define('NimbleTest', 'Run nimble test; optional backend', function(opts)
    local project = current_project()
    local backend = normalize_backend(opts.args)
    if not backend then
      return
    end
    if project and project.nimble then
      open_nim_terminal('nimble test --backend:' .. backend, project.root)
    else
      vim.notify('No .nimble project found', vim.log.levels.WARN)
    end
  end)

  define('NimbleInstall', 'Run nimble install; optional backend', function(opts)
    local project = current_project()
    local backend = normalize_backend(opts.args)
    if not backend then
      return
    end
    if project and project.nimble then
      open_nim_terminal('nimble install --backend:' .. backend, project.root)
    else
      vim.notify('No .nimble project found', vim.log.levels.WARN)
    end
  end)
end

local function setup_nim()
  local paths = get_nim_paths()
  setup_nim_server(paths)
  setup_nim_attach()
  setup_nim_diagnostics(paths)
  setup_nim_commands(paths)
end

return {
  {
    'neovim/nvim-lspconfig',
    config = setup_nim,
  },
}
