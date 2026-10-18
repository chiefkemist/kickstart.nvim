-- pi.nvim currently discards assistant text and finishes on agent_end, before
-- current Pi versions finish retries. Keep its commands/context/status UI, but
-- adapt the RPC transport and retain replies in a Markdown scratch pane.
local M = {}
local last_buffer

local function text_blocks(blocks)
  local keys = vim.tbl_keys(blocks)
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = blocks[key]
  end
  return table.concat(parts, '\n\n')
end

local function open_response(buf, focus)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    win = vim.api.nvim_open_win(buf, focus, { split = 'right', win = 0 })
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
  elseif focus then
    vim.api.nvim_set_current_win(win)
  end
end

local function render(session)
  local response = session.response
  local parts = vim.deepcopy(response.messages)
  local partial = text_blocks(response.blocks)
  if partial ~= '' then
    parts[#parts + 1] = partial
  end
  if #parts == 0 then
    return
  end
  if not response.buffer then
    response.buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(response.buffer, 'pi-response://' .. session.id)
    vim.bo[response.buffer].buftype = 'nofile'
    vim.bo[response.buffer].bufhidden = 'hide'
    vim.bo[response.buffer].swapfile = false
    vim.bo[response.buffer].filetype = 'markdown'
    vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = response.buffer, desc = 'Close pi response' })
    last_buffer = response.buffer
    open_response(response.buffer, false)
  end
  if vim.api.nvim_buf_is_valid(response.buffer) then
    vim.bo[response.buffer].modifiable = true
    vim.api.nvim_buf_set_lines(response.buffer, 0, -1, false, vim.split('# pi\n\n' .. table.concat(parts, '\n\n'), '\n', { plain = true }))
    vim.bo[response.buffer].modifiable = false
  end
end

local function start(session, cmd, payload, handlers)
  session.response = { messages = {}, blocks = {} }
  local tails = { stdout = '', stderr = '' }
  local process
  local function stderr(text)
    for _, value in ipairs(vim.split(text, '\n', { plain = true })) do
      handlers.on_stderr(value)
    end
  end
  local function active()
    return not session.cancelled and not session.closing
  end
  local function event(record)
    local response = session.response
    if record.type == 'message_start' and record.message.role == 'assistant' then
      response.blocks = {}
      response.error = nil
    elseif record.type == 'message_update' then
      local delta = record.assistantMessageEvent or {}
      local index = delta.contentIndex or 0
      if delta.type == 'text_delta' then
        response.blocks[index] = (response.blocks[index] or '') .. delta.delta
        render(session)
      elseif delta.type == 'text_end' then
        response.blocks[index] = delta.content
        render(session)
      elseif delta.type == 'error' then
        response.error = type(delta.error) == 'table' and delta.error.errorMessage or delta.reason
      end
      handlers.on_event { type = 'thinking' }
    elseif record.type == 'message_end' and record.message.role == 'assistant' then
      local message = record.message
      local blocks = {}
      for index, block in ipairs(message.content or {}) do
        if block.type == 'text' then
          blocks[index] = block.text
        end
      end
      local text = text_blocks(blocks)
      response.blocks = {}
      if text ~= '' then
        response.messages[#response.messages + 1] = text
        -- History entries must be individual lines for pi.nvim's status float.
        for _, line in ipairs(vim.split('Assistant:\n' .. text, '\n', { plain = true })) do
          require('pi.session').push(session, line)
        end
        render(session)
      end
      if message.stopReason == 'error' or message.stopReason == 'aborted' then
        response.error = message.errorMessage or 'Pi request failed'
      end
    elseif record.type == 'tool_execution_start' then
      handlers.on_event { type = 'tool_start', tool = record.toolName }
    elseif record.type == 'tool_execution_end' then
      handlers.on_event { type = 'tool_end', tool = record.toolName }
    elseif record.type == 'agent_settled' then
      if record.aborted or response.error then
        handlers.on_event { type = 'error', message = response.error or 'Pi request aborted' }
      else
        handlers.on_event { type = 'done' }
      end
    elseif record.type == 'response' then
      if record.success == false then
        handlers.on_event { type = 'error', message = record.error or 'Pi RPC command failed' }
      elseif record.command == 'prompt' and record.data and record.data.disposition == 'handled' then
        handlers.on_event { type = 'done' }
      end
    elseif record.type == 'extension_ui_request' then
      if vim.tbl_contains({ 'select', 'confirm', 'input', 'editor' }, record.method) then
        -- Never silently approve permissions or hang waiting for unsupported UI.
        process:write(vim.json.encode { type = 'extension_ui_response', id = record.id, cancelled = true } .. '\n')
        stderr 'Pi extension dialog cancelled; use the Pi CLI for interactive extension dialogs.'
      elseif record.method == 'notify' then
        stderr(record.message or '')
      end
    elseif record.type == 'extension_error' then
      stderr(tostring(record.error))
    end
    -- agent_end is deliberately ignored: retries/compaction may still follow.
  end
  local function line(stream, value)
    if not active() or value == '' then
      return
    end
    if stream == 'stderr' then
      handlers.on_stderr(value)
    else
      local ok, record = pcall(vim.json.decode, value)
      if ok and type(record) == 'table' then
        event(record)
      else
        handlers.on_error 'Invalid JSON in Pi RPC output'
      end
    end
  end
  local function feed(stream, err, data)
    if not active() then
      return
    end
    if err then
      handlers.on_error(tostring(err))
      return
    end
    tails[stream] = tails[stream] .. (data or '')
    while true do
      local newline = tails[stream]:find('\n', 1, true)
      if not newline then
        break
      end
      local value = tails[stream]:sub(1, newline - 1):gsub('\r$', '')
      tails[stream] = tails[stream]:sub(newline + 1)
      line(stream, value)
    end
  end
  local ok, result = pcall(
    vim.system,
    cmd,
    {
      text = true,
      stdin = true,
      stdout = vim.schedule_wrap(function(err, data)
        feed('stdout', err, data)
      end),
      stderr = vim.schedule_wrap(function(err, data)
        feed('stderr', err, data)
      end),
    },
    vim.schedule_wrap(function(exit)
      line('stdout', tails.stdout)
      line('stderr', tails.stderr)
      handlers.on_exit(exit)
    end)
  )
  if not ok then
    return nil, result
  end
  process = result
  local wrote, err = pcall(process.write, process, payload)
  if not wrote then
    pcall(process.kill, process, 15)
    return nil, err
  end
  return process
end

function M.setup(opts)
  require('pi.runner').start = start
  require('pi').setup(opts)
  vim.api.nvim_create_user_command('PiResponse', function()
    if last_buffer and vim.api.nvim_buf_is_valid(last_buffer) then
      open_response(last_buffer, true)
    else
      vim.notify('No pi response yet', vim.log.levels.INFO)
    end
  end, { desc = 'Reopen the last pi response', force = true })
end

return M
