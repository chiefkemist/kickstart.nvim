vim.keymap.set('t', '<esc><esc>', '<c-\\><c-n>')

local state = {
  floating = {
    buf = -1,
    win = -1,
  },
}

local function create_floating_window(opts)
  opts = opts or {}

  -- Get editor dimensions
  local width = vim.o.columns
  local height = vim.o.lines

  -- Calculate window size (default to 80% of screen)
  local win_width = opts.width or math.floor(width * 0.8)
  local win_height = opts.height or math.floor(height * 0.8)

  -- Calculate position to center the window
  local row = math.floor((height - win_height) / 2)
  local col = math.floor((width - win_width) / 2)

  -- Create buffer
  local buf = nil
  if vim.api.nvim_buf_is_valid(opts.buf) then
    buf = opts.buf
  else
    buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
  end

  -- Window configuration
  local win_opts = {
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
  }

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  return { buf = buf, win = win }
end

local toggle_floatterm = function()
  if not vim.api.nvim_win_is_valid(state.floating.win) then
    state.floating = create_floating_window { buf = state.floating.buf }
    -- state.floating = create_floating_window()
    -- print(vim.inspect(state.floating))
    if vim.bo[state.floating.buf].buftype ~= 'terminal' then
      vim.cmd.terminal()
    end
  else
    vim.api.nvim_win_hide(state.floating.win)
  end
end

vim.api.nvim_create_user_command('Floatterm', toggle_floatterm, {})
vim.keymap.set({ 'n', 't' }, '<space>tt', toggle_floatterm)

-- Default 80% of screen, centered
-- local buf, win = create_floating_window()

-- Custom size
-- local buf, win = create_floating_window { width = 100, height = 30 }

-- Only specify one dimension

return {}
