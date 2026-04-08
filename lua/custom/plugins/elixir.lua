local repl_ns = vim.api.nvim_create_namespace 'custom-elixir-repl'
local repl_states = {}
local repl_active_modes = {}

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

local function setup_livebook_highlighting()
  pcall(vim.treesitter.language.register, 'markdown', 'livebook')
end

local function lsp_capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  local ok, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
  if ok then
    capabilities = vim.tbl_deep_extend('force', capabilities, cmp_nvim_lsp.default_capabilities())
  end
  return capabilities
end

local function current_elixir_root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then
    return vim.uv.cwd()
  end

  local matches = vim.fs.find({ 'mix.exs' }, { upward = true, limit = 2, path = name })
  local child_or_root, maybe_umbrella = unpack(matches)
  local mix_file = maybe_umbrella or child_or_root

  if mix_file then
    return vim.fs.dirname(mix_file)
  end

  return vim.fs.dirname(name)
end

local function has_locations(result)
  if not result then
    return false
  end

  if result.uri or result.targetUri then
    return true
  end

  return vim.islist(result) and not vim.tbl_isempty(result)
end

-- Expert can attach before its project engine/search index is ready, so early
-- location requests may be ignored even though the client is already attached.
local function request_when_expert_ready(bufnr, client, method, params, action, retries_left)
  retries_left = retries_left or 12

  client:request(method, params, function(err, result)
    if err then
      return
    end

    if has_locations(result) then
      vim.schedule(function()
        action()
      end)
      return
    end

    if retries_left <= 0 then
      vim.schedule(function()
        action()
      end)
      return
    end

    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(bufnr) and client:is_stopped() == false then
        request_when_expert_ready(bufnr, client, method, params, action, retries_left - 1)
      end
    end, 500)
  end, bufnr)
end

local function elixir_goto_definition(bufnr, client)
  request_when_expert_ready(bufnr, client, 'textDocument/definition', vim.lsp.util.make_position_params(0, client.offset_encoding), function()
    vim.lsp.buf.definition()
  end)
end

local function elixir_find_references(bufnr, client)
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.context = { includeDeclaration = true }
  request_when_expert_ready(bufnr, client, 'textDocument/references', params, function()
    vim.lsp.buf.references(nil)
  end)
end

local function has_mix_project(root)
  return vim.fs.find({ 'mix.exs' }, { path = root, upward = false, limit = 1 })[1] ~= nil
end

local function default_repl_mode(root)
  if has_mix_project(root) then
    return 'mix'
  end
  return 'plain'
end

local function normalize_repl_mode(root, mode)
  mode = mode or repl_active_modes[root] or default_repl_mode(root)
  if (mode == 'mix' or mode == 'phoenix') and not has_mix_project(root) then
    vim.notify('No mix.exs found for this project', vim.log.levels.WARN)
    return default_repl_mode(root)
  end
  return mode
end

local function repl_mode_label(mode)
  if mode == 'plain' then
    return 'IEx'
  elseif mode == 'mix' then
    return 'IEx -S mix'
  elseif mode == 'phoenix' then
    return 'IEx -S mix phx.server'
  end
  return mode
end

local function repl_command(mode)
  local iex = vim.fn.exepath 'iex'
  if iex == '' then
    iex = 'iex'
  end

  if mode == 'plain' then
    return { iex }
  elseif mode == 'mix' then
    return { iex, '-S', 'mix' }
  elseif mode == 'phoenix' then
    return { iex, '-S', 'mix', 'phx.server' }
  end

  return { iex }
end

local function repl_key(root, mode)
  return root .. '::' .. mode
end

local function exs_tempfile(prefix, text)
  local dir = vim.fn.stdpath 'cache' .. '/elixir-eval'
  vim.fn.mkdir(dir, 'p')

  local name = string.format('%s-%d-%06d.exs', prefix, vim.loop.hrtime(), math.random(0, 999999))
  local path = dir .. '/' .. name
  local fd = assert(vim.uv.fs_open(path, 'w', 420))
  assert(vim.uv.fs_write(fd, text, -1))
  assert(vim.uv.fs_close(fd))
  return path
end

local function elixir_string(value)
  return string.format('%q', value)
end

local function is_job_running(job_id)
  if not job_id or job_id <= 0 then
    return false
  end

  local ok, result = pcall(vim.fn.jobwait, { job_id }, 0)
  return ok and result[1] == -1
end

local function repl_width()
  return math.max(44, math.floor(vim.o.columns * 0.38))
end

local function clear_inline_results(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, repl_ns, 0, -1)
  end
end

local function state_for_root(root, mode)
  local key = repl_key(root, mode)
  local state = repl_states[key]
  if state and vim.api.nvim_buf_is_valid(state.bufnr) and is_job_running(state.job_id) then
    return state
  end

  repl_states[key] = nil
  return nil
end

local function flush_repl_queue(state)
  if not state.ready or vim.tbl_isempty(state.queue) then
    return
  end

  for _, command in ipairs(state.queue) do
    if is_job_running(state.job_id) then
      vim.api.nvim_chan_send(state.job_id, command .. '\r')
    end
  end

  state.queue = {}
end

local function sanitize_repl_line(line)
  line = line:gsub('\27%[[0-9;?]*[%a~]', '')
  line = line:gsub('^iex%([^)]*%)>+%s*', '')
  line = line:gsub('^%.%.%.%(%d+%)>+%s*', '')
  return vim.trim(line)
end

local function summarize_result(lines, is_error)
  local first = vim.trim(lines[1] or '')
  first = first:gsub('^ok:', ''):gsub('^error:', '')
  if first == '' then
    first = is_error and 'error' or 'ok'
  end
  if #first > 140 then
    first = first:sub(1, 137) .. '...'
  end
  return (is_error and '!! ' or '=> ') .. first
end

local function finish_pending_eval(state, id, pending, is_error)
  if vim.api.nvim_buf_is_valid(pending.source_bufnr) then
    clear_inline_results(pending.source_bufnr)
    vim.api.nvim_buf_set_extmark(pending.source_bufnr, repl_ns, pending.row, 0, {
      virt_text = { { summarize_result(pending.lines, is_error), is_error and 'DiagnosticError' or 'DiagnosticInfo' } },
      virt_text_pos = 'eol',
      hl_mode = 'combine',
    })
  end

  os.remove(pending.tempfile)
  state.pending[id] = nil
end

local function process_repl_line(state, raw_line)
  local line = sanitize_repl_line(raw_line)
  if line == '' then
    return
  end

  for id, pending in pairs(state.pending) do
    if pending.capture then
      if line:find(pending.done_marker, 1, true) then
        finish_pending_eval(state, id, pending, pending.is_error)
      elseif line ~= ':ok' and not line:match '^IO%.puts%(' and not line:match '^try do' then
        table.insert(pending.lines, line)
      end
    elseif line:match '^ok:' then
      pending.capture = true
      pending.is_error = false
      pending.lines = { line }
    elseif line:match '^error:' then
      pending.capture = true
      pending.is_error = true
      pending.lines = { line }
    end
  end
end

local function attach_repl_stdout(state, data)
  if not data or vim.tbl_isempty(data) then
    return
  end

  local chunk = table.concat(data, '\n')
  if chunk == '' then
    return
  end

  state.stdout = state.stdout .. chunk .. '\n'

  if not state.ready and (state.stdout:find('Interactive Elixir', 1, true) or state.stdout:find('iex(', 1, true)) then
    state.ready = true
    flush_repl_queue(state)
  end

  while true do
    local newline = state.stdout:find('\n', 1, true)
    if not newline then
      break
    end

    local line = state.stdout:sub(1, newline - 1):gsub('\r', '')
    state.stdout = state.stdout:sub(newline + 1)
    process_repl_line(state, line)
  end
end

local function ensure_repl(root, opts)
  opts = opts or {}
  local mode = normalize_repl_mode(root, opts.mode)
  local key = repl_key(root, mode)

  local state = state_for_root(root, mode)
  if state then
    repl_active_modes[root] = mode
    local winid = state.winid
    if not winid or not vim.api.nvim_win_is_valid(winid) then
      local current = vim.api.nvim_get_current_win()
      vim.cmd 'botright vsplit'
      winid = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_width(winid, repl_width())
      vim.api.nvim_win_set_buf(winid, state.bufnr)
      state.winid = winid
      if not opts.focus then
        vim.api.nvim_set_current_win(current)
      end
    end
    return state
  end

  local previous = vim.api.nvim_get_current_win()
  vim.cmd 'botright vsplit'
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(winid, repl_width())

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].swapfile = false

  state = {
    root = root,
    mode = mode,
    bufnr = bufnr,
    winid = winid,
    queue = {},
    pending = {},
    ready = false,
    stdout = '',
  }

  repl_states[key] = state
  repl_active_modes[root] = mode

  state.job_id = vim.fn.termopen(repl_command(mode), {
    cwd = root,
    on_stdout = function(_, data)
      attach_repl_stdout(state, data)
    end,
    on_exit = function()
      state.job_id = nil
      state.winid = nil
      if repl_active_modes[root] == mode then
        repl_active_modes[root] = nil
      end
    end,
  })

  vim.api.nvim_buf_set_name(bufnr, ('Elixir REPL [%s]: %s'):format(repl_mode_label(mode), root))

  if not opts.focus then
    vim.api.nvim_set_current_win(previous)
  end

  return state
end

local function send_to_repl(state, command)
  if not state or not is_job_running(state.job_id) then
    return false
  end

  if state.ready then
    vim.api.nvim_chan_send(state.job_id, command .. '\r')
  else
    table.insert(state.queue, command)
  end

  return true
end

local function build_eval_command(opts)
  local done_marker = '__NVIM_ELIXIR_DONE_' .. opts.id .. '__'
  local tempfile = elixir_string(opts.tempfile)
  local source_file = elixir_string(opts.source_file)

  local expr = table.concat({
    'try do',
    '__nvim_code = File.read!(' .. tempfile .. ')',
    '{__nvim_value, _} = Code.eval_string(__nvim_code, [], file: ' .. source_file .. ', line: ' .. opts.start_line .. ')',
    'IO.puts("ok:" <> inspect(__nvim_value, pretty: true, limit: :infinity, printable_limit: :infinity))',
    'rescue',
    '__nvim_error -> IO.puts("error:" <> Exception.format(:error, __nvim_error, __STACKTRACE__))',
    'catch',
    '__nvim_kind, __nvim_value -> IO.puts("error:" <> Exception.format(__nvim_kind, __nvim_value, __STACKTRACE__))',
    'end',
    'IO.puts(' .. elixir_string(done_marker) .. ')',
  }, '; ')

  return expr, done_marker
end

local function eval_text(text, bufnr, start_line, row)
  if text == '' then
    vim.notify('Nothing to evaluate', vim.log.levels.WARN)
    return
  end

  local root = current_elixir_root(bufnr)
  local state = ensure_repl(root, { mode = repl_active_modes[root] or default_repl_mode(root) })
  local tempfile = exs_tempfile('selection', text)
  local id = tostring(vim.loop.hrtime())
  local source_file = vim.api.nvim_buf_get_name(bufnr)
  if source_file == '' then
    source_file = tempfile
  end

  local command, done_marker = build_eval_command {
    id = id,
    tempfile = tempfile,
    source_file = source_file,
    start_line = start_line,
  }

  state.pending[id] = {
    source_bufnr = bufnr,
    row = math.max(row, 0),
    tempfile = tempfile,
    done_marker = done_marker,
    capture = false,
    is_error = false,
    lines = {},
  }

  clear_inline_results(bufnr)

  if not send_to_repl(state, command) then
    state.pending[id] = nil
    os.remove(tempfile)
    vim.notify('Elixir REPL is not running', vim.log.levels.ERROR)
  end
end

local function enclosing_top_level_form(bufnr, start_row, end_row)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'elixir')
  if not ok or not parser then
    return nil, nil, nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil, nil, nil
  end

  local root = tree:root()
  local pieces = {}
  local first_row, last_row

  for child in root:iter_children() do
    if child:named() then
      local sr, _, er, _ = child:range()
      if sr <= end_row and er >= start_row then
        pieces[#pieces + 1] = vim.treesitter.get_node_text(child, bufnr)
        first_row = first_row or sr
        last_row = er
      end
    end
  end

  if #pieces == 0 then
    return nil, nil, nil
  end

  return table.concat(pieces, '\n'), first_row + 1, last_row
end

local function should_use_contextual_form(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name:match('%.ex$') ~= nil
end

local function current_line_text(bufnr)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''

  if should_use_contextual_form(bufnr) then
    local text, start_line, end_row = enclosing_top_level_form(bufnr, row - 1, row - 1)
    if text and text ~= '' then
      return text, start_line, end_row
    end
  end

  return line, row, row - 1
end

local function selection_text_from_bounds(bufnr, start_row, start_col, end_row, end_col, visual_mode)
  if end_row < start_row or (end_row == start_row and end_col < start_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  if vim.tbl_isempty(lines) then
    return '', start_row + 1, start_row
  end

  if visual_mode == 'V' then
    return table.concat(lines, '\n'), start_row + 1, end_row
  end

  lines[1] = string.sub(lines[1], start_col + 1)
  lines[#lines] = string.sub(lines[#lines], 1, math.min(end_col + 1, #lines[#lines]))

  return table.concat(lines, '\n'), start_row + 1, end_row
end

local function active_visual_selection_text(bufnr)
  local mode = vim.fn.mode()
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\022' then
    return nil
  end

  local anchor = vim.fn.getpos 'v'
  local cursor = vim.api.nvim_win_get_cursor(0)
  local text, start_line, end_row = selection_text_from_bounds(bufnr, anchor[2] - 1, math.max(anchor[3] - 1, 0), cursor[1] - 1, cursor[2], mode)

  if should_use_contextual_form(bufnr) then
    local contextual, contextual_start, contextual_end = enclosing_top_level_form(bufnr, start_line - 1, end_row)
    if contextual and contextual ~= '' then
      return contextual, contextual_start, contextual_end
    end
  end

  return text, start_line, end_row
end

local function visual_selection_text(bufnr)
  local text, start_line, end_row = active_visual_selection_text(bufnr)
  if text then
    return text, start_line, end_row
  end

  local start_pos = vim.fn.getpos "'<"
  local end_pos = vim.fn.getpos "'>"
  local text2, start_line2, end_row2 = selection_text_from_bounds(bufnr, start_pos[2] - 1, math.max(start_pos[3] - 1, 0), end_pos[2] - 1, math.max(end_pos[3] - 1, 0), vim.fn.visualmode())

  if should_use_contextual_form(bufnr) then
    local contextual, contextual_start, contextual_end = enclosing_top_level_form(bufnr, start_line2 - 1, end_row2)
    if contextual and contextual ~= '' then
      return contextual, contextual_start, contextual_end
    end
  end

  return text2, start_line2, end_row2
end

local function buffer_text(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local row = math.max(vim.api.nvim_win_get_cursor(0)[1] - 1, 0)
  return table.concat(lines, '\n'), 1, row
end

local function open_repl_for_current_buffer(mode)
  ensure_repl(current_elixir_root(0), { focus = false, mode = mode })
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

local function setup_hover_echo(bufnr, client, group_name)
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

  local group = vim.api.nvim_create_augroup(group_name .. '-' .. bufnr, { clear = true })
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
      clear_inline_results(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ 'InsertEnter', 'BufLeave' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      clear_hover()
      clear_inline_results(bufnr)
    end,
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
      clear_inline_results(bufnr)
    end,
  })
end

local function enable_lsp_features()
  local group = vim.api.nvim_create_augroup('custom-elixir-lsp', { clear = true })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client or client.name ~= 'expert' then
        return
      end

      setup_hover_echo(args.buf, client, 'custom-elixir-hover')

      if client.server_capabilities.inlayHintProvider then
        vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
      end

      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(args.buf) then
          return
        end

        vim.keymap.set('n', 'gd', function()
          elixir_goto_definition(args.buf, client)
        end, { buffer = args.buf, desc = 'Elixir: Goto Definition', silent = true })

        vim.keymap.set('n', 'gr', function()
          elixir_find_references(args.buf, client)
        end, { buffer = args.buf, desc = 'Elixir: Find References', silent = true })
      end)
    end,
  })
end

local function setup_elixir_server()
  vim.lsp.config('expert', {
    capabilities = lsp_capabilities(),
  })

  vim.lsp.enable 'expert'
end

local function setup_commands_and_keymaps()
  if vim.g.custom_elixir_repl_setup_done then
    return
  end
  vim.g.custom_elixir_repl_setup_done = true

  vim.api.nvim_create_user_command('ElixirReplOpen', function()
    open_repl_for_current_buffer()
  end, { desc = 'Open the default Elixir REPL for the current project' })

  vim.api.nvim_create_user_command('ElixirReplOpenPlain', function()
    open_repl_for_current_buffer 'plain'
  end, { desc = 'Open plain IEx in a vertical split' })

  vim.api.nvim_create_user_command('ElixirReplOpenMix', function()
    open_repl_for_current_buffer 'mix'
  end, { desc = 'Open IEx -S mix in a vertical split' })

  vim.api.nvim_create_user_command('ElixirReplOpenPhoenix', function()
    open_repl_for_current_buffer 'phoenix'
  end, { desc = 'Open IEx -S mix phx.server in a vertical split' })

  vim.api.nvim_create_user_command('ElixirReplEvalLine', function()
    local text, start_line, row = current_line_text(0)
    eval_text(text, 0, start_line, row)
  end, { desc = 'Evaluate the current line in IEx' })

  vim.api.nvim_create_user_command('ElixirReplEvalSelection', function()
    local text, start_line, row = visual_selection_text(0)
    eval_text(text, 0, start_line, row)
  end, { range = true, desc = 'Evaluate the current visual selection in IEx' })

  vim.api.nvim_create_user_command('ElixirReplEvalBuffer', function()
    local text, start_line, row = buffer_text(0)
    eval_text(text, 0, start_line, row)
  end, { desc = 'Evaluate the current buffer in IEx' })

  vim.api.nvim_create_user_command('ElixirReplClearInline', function()
    clear_inline_results(0)
  end, { desc = 'Clear inline Elixir eval results' })

  local group = vim.api.nvim_create_augroup('custom-elixir-repl-ft', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'elixir', 'eelixir', 'heex', 'surface' },
    callback = function(args)
      local opts = { buffer = args.buf, silent = true }
      vim.keymap.set('n', '<localleader>ro', function()
        open_repl_for_current_buffer()
      end, vim.tbl_extend('force', opts, { desc = 'Elixir: Open Default REPL' }))
      vim.keymap.set('n', '<localleader>ri', function()
        open_repl_for_current_buffer 'plain'
      end, vim.tbl_extend('force', opts, { desc = 'Elixir: Open Plain IEx' }))
      vim.keymap.set('n', '<localleader>rm', function()
        open_repl_for_current_buffer 'mix'
      end, vim.tbl_extend('force', opts, { desc = 'Elixir: Open IEx -S mix' }))
      vim.keymap.set('n', '<localleader>rp', function()
        open_repl_for_current_buffer 'phoenix'
      end, vim.tbl_extend('force', opts, { desc = 'Elixir: Open IEx -S mix phx.server' }))
      vim.keymap.set('n', '<localleader>rl', function()
        local text, start_line, row = current_line_text(args.buf)
        eval_text(text, args.buf, start_line, row)
      end, vim.tbl_extend('force', opts, { desc = 'Elixir: Eval Line' }))
      vim.keymap.set('n', '<localleader>rb', function()
        local text, start_line, row = buffer_text(args.buf)
        eval_text(text, args.buf, start_line, row)
      end, vim.tbl_extend('force', opts, { desc = 'Elixir: Eval Buffer' }))
      vim.keymap.set('n', '<localleader>rc', function()
        clear_inline_results(args.buf)
      end, vim.tbl_extend('force', opts, { desc = 'Elixir: Clear Inline Results' }))
      vim.keymap.set('x', '<localleader>re', function()
        local text, start_line, row = active_visual_selection_text(args.buf)
        if not text then
          text, start_line, row = visual_selection_text(args.buf)
        end
        eval_text(text or '', args.buf, start_line or vim.fn.line('.'), row or (vim.fn.line('.') - 1))
      end, vim.tbl_extend('force', opts, { desc = 'Elixir: Eval Selection' }))
    end,
  })
end

return {
  {
    'neovim/nvim-lspconfig',
    opts = function(_, opts)
      ensure_treesitter_parsers { 'elixir', 'eex', 'heex', 'markdown', 'markdown_inline' }
      setup_livebook_highlighting()
      setup_elixir_server()

      enable_lsp_features()
      setup_commands_and_keymaps()

      return opts
    end,
  },
}
