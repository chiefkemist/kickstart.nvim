local floatterm_ns = vim.api.nvim_create_namespace 'floatterm'
local floatterm_backdrop_ns = vim.api.nvim_create_namespace 'floatterm_backdrop'

local palette = {
  bg = '#0b0f14',
  bg_alt = '#111826',
  bg_backdrop = '#05080d',
  fg = '#e6edf3',
  border = '#6cb6ff',

  black = '#3b4252',
  red = '#ff6b6b',
  green = '#7ee787',
  yellow = '#ffd866',
  blue = '#6cb6ff',
  magenta = '#d2a8ff',
  cyan = '#56d4dd',
  white = '#d9e0ee',

  bright_black = '#6b7280',
  bright_red = '#ff8e8e',
  bright_green = '#8ef0a6',
  bright_yellow = '#ffe082',
  bright_blue = '#8cc8ff',
  bright_magenta = '#e2b8ff',
  bright_cyan = '#7ce7ff',
  bright_white = '#ffffff',
}

local terminal_colors = {
  palette.black,
  palette.red,
  palette.green,
  palette.yellow,
  palette.blue,
  palette.magenta,
  palette.cyan,
  palette.white,
  palette.bright_black,
  palette.bright_red,
  palette.bright_green,
  palette.bright_yellow,
  palette.bright_blue,
  palette.bright_magenta,
  palette.bright_cyan,
  palette.bright_white,
}

local state = {
  floating = {
    buf = -1,
    win = -1,
  },
  backdrop = {
    buf = -1,
    win = -1,
  },
}

local function is_neovide()
  return vim.g.neovide == true or vim.g.neovide == 1
end

local function configure_neovide_float_blur()
  if not is_neovide() then
    return
  end

  if vim.g.neovide_floating_blur_amount_x == nil then
    vim.g.neovide_floating_blur_amount_x = 8.0
  end

  if vim.g.neovide_floating_blur_amount_y == nil then
    vim.g.neovide_floating_blur_amount_y = 8.0
  end

  if vim.g.neovide_floating_shadow == nil then
    vim.g.neovide_floating_shadow = true
  end
end

configure_neovide_float_blur()

local function apply_window_theme(win)
  vim.api.nvim_set_hl(floatterm_ns, 'Normal', { fg = palette.fg, bg = palette.bg })
  vim.api.nvim_set_hl(floatterm_ns, 'NormalFloat', { fg = palette.fg, bg = palette.bg })
  vim.api.nvim_set_hl(floatterm_ns, 'FloatBorder', { fg = palette.border, bg = palette.bg })
  vim.api.nvim_set_hl(floatterm_ns, 'FloatTitle', { fg = palette.border, bg = palette.bg, bold = true })
  vim.api.nvim_set_hl(floatterm_ns, 'CursorLine', { bg = palette.bg_alt })
  vim.api.nvim_set_hl(floatterm_ns, 'EndOfBuffer', { fg = palette.bg, bg = palette.bg })
  vim.api.nvim_set_hl(floatterm_ns, 'SignColumn', { bg = palette.bg })
  vim.api.nvim_set_hl(floatterm_ns, 'WinSeparator', { fg = palette.border, bg = palette.bg })

  vim.api.nvim_win_set_hl_ns(win, floatterm_ns)
  vim.wo[win].winblend = 0
  vim.wo[win].cursorline = false
end

local function apply_backdrop_theme(win)
  vim.api.nvim_set_hl(floatterm_backdrop_ns, 'Normal', { bg = palette.bg_backdrop })
  vim.api.nvim_set_hl(floatterm_backdrop_ns, 'NormalFloat', { bg = palette.bg_backdrop })
  vim.api.nvim_set_hl(floatterm_backdrop_ns, 'EndOfBuffer', { fg = palette.bg_backdrop, bg = palette.bg_backdrop })

  vim.api.nvim_win_set_hl_ns(win, floatterm_backdrop_ns)
  vim.wo[win].winblend = is_neovide() and 35 or 0
end

local function apply_terminal_palette(buf)
  for i, color in ipairs(terminal_colors) do
    vim.api.nvim_buf_set_var(buf, 'terminal_color_' .. (i - 1), color)
  end
end

local function terminal_job_is_running(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= 'terminal' then
    return false
  end

  local channel = vim.bo[buf].channel
  if not channel or channel == 0 then
    return false
  end

  return vim.fn.jobwait({ channel }, 0)[1] == -1
end

local function create_terminal_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'
  apply_terminal_palette(buf)
  return buf
end

local function ensure_backdrop_buffer()
  if vim.api.nvim_buf_is_valid(state.backdrop.buf) then
    return state.backdrop.buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'
  state.backdrop.buf = buf
  return buf
end

local function get_layout(opts)
  opts = opts or {}

  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight

  local max_width = math.max(20, editor_width - 4)
  local max_height = math.max(8, editor_height - 4)

  local win_width = math.max(20, math.min(opts.width or math.floor(editor_width * 0.85), max_width))
  local win_height = math.max(8, math.min(opts.height or math.floor(editor_height * 0.85), max_height))

  return {
    editor_width = editor_width,
    editor_height = editor_height,
    width = win_width,
    height = win_height,
    row = math.max(0, math.floor((editor_height - win_height) / 2) - 1),
    col = math.max(0, math.floor((editor_width - win_width) / 2)),
  }
end

local function get_backdrop_config()
  local layout = get_layout()
  return {
    relative = 'editor',
    width = layout.editor_width,
    height = layout.editor_height,
    row = 0,
    col = 0,
    style = 'minimal',
    border = 'none',
    focusable = false,
    zindex = 50,
    noautocmd = true,
  }
end

local function get_float_config(opts)
  local layout = get_layout(opts)
  return {
    relative = 'editor',
    width = layout.width,
    height = layout.height,
    row = layout.row,
    col = layout.col,
    style = 'minimal',
    border = 'rounded',
    title = ' terminal ',
    title_pos = 'center',
    zindex = 60,
  }
end

local function open_backdrop_window()
  local buf = ensure_backdrop_buffer()
  local win = vim.api.nvim_open_win(buf, false, get_backdrop_config())
  apply_backdrop_theme(win)
  return { buf = buf, win = win }
end

local function create_floating_window(opts)
  opts = opts or {}

  local buf = opts.buf
  if not vim.api.nvim_buf_is_valid(buf) then
    buf = create_terminal_buffer()
  end

  local win = vim.api.nvim_open_win(buf, true, get_float_config(opts))
  apply_window_theme(win)

  return { buf = buf, win = win }
end

local function refresh_open_windows()
  configure_neovide_float_blur()

  if vim.api.nvim_win_is_valid(state.backdrop.win) then
    vim.api.nvim_win_set_config(state.backdrop.win, get_backdrop_config())
    apply_backdrop_theme(state.backdrop.win)
  end

  if vim.api.nvim_win_is_valid(state.floating.win) then
    vim.api.nvim_win_set_config(state.floating.win, get_float_config())
    apply_window_theme(state.floating.win)
  end
end

local function hide_floatterm()
  if vim.api.nvim_win_is_valid(state.floating.win) then
    vim.api.nvim_win_hide(state.floating.win)
  end

  if vim.api.nvim_win_is_valid(state.backdrop.win) then
    vim.api.nvim_win_hide(state.backdrop.win)
  end
end

local function ensure_terminal_buffer()
  local buf = state.floating.buf

  if vim.api.nvim_buf_is_valid(buf) then
    if vim.bo[buf].buftype ~= 'terminal' then
      apply_terminal_palette(buf)
      return buf, false
    end

    if terminal_job_is_running(buf) then
      return buf, true
    end

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  buf = create_terminal_buffer()
  state.floating.buf = buf
  return buf, false
end

local function open_terminal(buf)
  apply_terminal_palette(buf)
  vim.api.nvim_buf_call(buf, function()
    local job = vim.fn.jobstart({ vim.o.shell }, {
      term = true,
      cwd = vim.fn.getcwd(),
    })

    if job <= 0 then
      vim.notify('Failed to start floating terminal shell', vim.log.levels.ERROR)
      return
    end

    vim.cmd.startinsert()
  end)
end

local function toggle_floatterm()
  if vim.api.nvim_win_is_valid(state.floating.win) then
    hide_floatterm()
    return
  end

  local buf, terminal_running = ensure_terminal_buffer()
  state.backdrop = open_backdrop_window()
  state.floating = create_floating_window { buf = buf }

  if terminal_running then
    vim.cmd.startinsert()
  else
    open_terminal(state.floating.buf)
  end
end

vim.api.nvim_create_autocmd('ColorScheme', {
  callback = refresh_open_windows,
})

vim.api.nvim_create_autocmd('VimResized', {
  callback = refresh_open_windows,
})

vim.api.nvim_create_user_command('Floatterm', toggle_floatterm, {})
vim.keymap.set({ 'n', 't' }, '<space>tt', toggle_floatterm, { desc = 'Toggle floating terminal' })

return {}
