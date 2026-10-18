-- Run with: nvim --headless '+luafile tests/pi.lua'
-- Real subprocesses, synthetic RPC records: no model requests or credentials.
local ok, err = pcall(function()
  require('lazy').load { plugins = { 'pi.nvim' } }
  local pi = require 'pi'
  local function message(text, stop, error_message)
    return {
      type = 'message_end',
      message = { role = 'assistant', content = { { type = 'text', text = text } }, stopReason = stop or 'stop', errorMessage = error_message },
    }
  end
  local function run(events, expected_status)
    local code = ([=[
import sys,json,time
sys.stdin.readline()
records=json.loads(%s)
for record in records:
    data=json.dumps(record,ensure_ascii=False)+'\r\n'
    cut=len(data.encode('utf-8'))//2
    raw=data.encode('utf-8')
    sys.stdout.buffer.write(raw[:cut]);sys.stdout.buffer.flush()
    time.sleep(0.005)
    sys.stdout.buffer.write(raw[cut:]);sys.stdout.buffer.flush()
    if record.get('type')=='extension_ui_request' and record.get('method')=='confirm':
        reply=json.loads(sys.stdin.readline())
        assert reply['id']==record['id'] and reply.get('cancelled') is True
sys.stdin.read()
]=]):format(vim.json.encode(vim.json.encode(events)))
    pi.run {
      message = 'Test response rendering',
      cmd = { 'python3', '-u', '-c', code },
      build_context = function()
        return 'test context'
      end,
      skip_reload = true,
    }
    local session = pi._get_active_session()
    assert(session, 'Request did not start')
    assert(
      vim.wait(10000, function()
        return not pi.is_running()
      end, 10),
      'RPC request hung'
    )
    assert(session.status == expected_status, session.last_error or session.status)
    session.process:wait(2000)
    return session
  end
  local start = { type = 'message_start', message = { role = 'assistant' } }
  local settled = { type = 'agent_settled', aborted = false }
  local session = run({
    start,
    { type = 'message_update', assistantMessageEvent = { type = 'thinking_delta', delta = 'Do not display reasoning' } },
    { type = 'message_update', assistantMessageEvent = { type = 'text_delta', contentIndex = 0, delta = 'Hello ' } },
    { type = 'message_update', assistantMessageEvent = { type = 'text_delta', contentIndex = 0, delta = 'world' } },
    message 'Hello world!\n\nUnicode: λ 😀',
    { type = 'agent_end', willRetry = false },
    settled,
  }, 'done')
  local buf = session.response.buffer
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  assert(text == '# pi\n\nHello world!\n\nUnicode: λ 😀', text)
  assert(vim.bo[buf].filetype == 'markdown' and not vim.bo[buf].modifiable)
  assert(table.concat(session.history, '\n'):find('Hello world!', 1, true))
  vim.api.nvim_win_close(vim.fn.bufwinid(buf), true)
  assert(vim.api.nvim_buf_is_valid(buf), 'Closing response discarded it')
  vim.cmd.PiResponse()
  assert(vim.api.nvim_get_current_buf() == buf)

  session = run({
    start,
    message('', 'error', 'Temporary provider error'),
    { type = 'agent_end', willRetry = true },
    { type = 'auto_retry_start', attempt = 1 },
    start,
    message 'Retried successfully',
    { type = 'agent_end', willRetry = false },
    settled,
  }, 'done')
  assert(session.response.messages[1] == 'Retried successfully')
  session = run({ start, message('', 'error', 'Authentication failed'), settled }, 'error')
  assert(session.last_error == 'Authentication failed')
  session = run({ { type = 'response', success = false, error = 'Invalid model' } }, 'error')
  assert(session.last_error == 'Invalid model')
  session = run({
    { type = 'extension_ui_request', id = 'permission', method = 'confirm', title = 'Dangerous action?' },
    { type = 'extension_ui_request', id = 'notice', method = 'notify', message = 'First line\nSecond line' },
    start,
    message 'Permission was not granted',
    settled,
  }, 'done')
  assert(table.concat(session.history, '\n'):find('Second line', 1, true))
  run({ { type = 'response', command = 'prompt', success = true, data = { disposition = 'handled' } } }, 'done')

  -- A provider exit without completion must not leave the spinner running.
  pi.run {
    message = 'Exit test',
    cmd = { 'python3', '-c', 'import sys; sys.stdin.readline(); sys.exit(1)' },
    build_context = function()
      return ''
    end,
  }
  assert(vim.wait(10000, function()
    return not pi.is_running()
  end, 10))
  assert(pi._get_last_session().status == 'error')

  pi.run {
    message = 'Cancel test',
    cmd = { 'python3', '-c', 'import sys,time; sys.stdin.readline(); time.sleep(30)' },
    build_context = function()
      return ''
    end,
  }
  session = pi._get_active_session()
  pi.cancel()
  assert(not pi.is_running())
  session.process:wait(2000)
  assert(session.cancelled)
  assert(vim.v.errmsg == '', vim.v.errmsg)
  print 'PASS: streaming/final replies, Unicode/chunked RPC, persistent pane, retries, errors, extension dialogs, process exits, cancellation'
end)
if not ok then
  io.stderr:write(tostring(err) .. '\n')
  vim.cmd 'cquit 1'
else
  vim.cmd 'qa!'
end
