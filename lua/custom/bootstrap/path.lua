local M = {}

local is_windows = vim.fn.has 'win32' == 1 or vim.fn.has 'win64' == 1
local path_sep = is_windows and ';' or ':'

local function home_dir()
  return vim.env.HOME or vim.env.USERPROFILE
end

local function is_dir(path)
  return path and path ~= '' and vim.fn.isdirectory(path) == 1
end

local function normalize_path(path)
  if not is_windows then
    return path
  end

  return path and path:lower() or path
end

local function path_entries(path)
  return vim.gsplit(path or '', path_sep, { plain = true, trimempty = true })
end

local function path_contains(path, target)
  local normalized_target = normalize_path(target)
  for entry in path_entries(path) do
    if normalize_path(entry) == normalized_target then
      return true
    end
  end

  return false
end

local function prepend_existing_paths(paths)
  local current_path = vim.env.PATH or ''
  local seen = {}

  for entry in path_entries(current_path) do
    seen[normalize_path(entry)] = true
  end

  local additions = {}
  for _, path in ipairs(paths) do
    local normalized = normalize_path(path)
    if is_dir(path) and not seen[normalized] then
      table.insert(additions, path)
      seen[normalized] = true
    end
  end

  if #additions == 0 then
    return
  end

  vim.env.PATH = table.concat(additions, path_sep) .. (current_path ~= '' and path_sep .. current_path or '')
end

local function read_login_shell_path()
  if is_windows then
    return nil
  end

  local shell = vim.env.SHELL
  if not shell or shell == '' or vim.fn.executable(shell) ~= 1 then
    return nil
  end

  local result = vim.system({ shell, '-lic', 'printf %s "$PATH"' }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local shell_path = vim.trim(result.stdout or '')
  return shell_path ~= '' and shell_path or nil
end

local function path_sync_markers(home)
  if is_windows then
    return vim.tbl_filter(function(path)
      return path ~= nil
    end, {
      home and vim.fs.joinpath(home, 'scoop', 'shims') or nil,
      home and vim.fs.joinpath(home, '.cargo', 'bin') or nil,
      home and vim.fs.joinpath(home, '.local', 'bin') or nil,
      vim.env.ProgramData and vim.fs.joinpath(vim.env.ProgramData, 'chocolatey', 'bin') or nil,
    })
  end

  return vim.tbl_filter(function(path)
    return path ~= nil
  end, {
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/local/sbin',
    home and vim.fs.joinpath(home, '.local', 'bin') or nil,
    home and vim.fs.joinpath(home, '.cargo', 'bin') or nil,
    home and vim.fs.joinpath(home, '.bun', 'bin') or nil,
  })
end

local function should_sync_path_from_shell()
  local current_path = vim.env.PATH or ''
  if current_path == '' then
    return true
  end

  for _, marker in ipairs(path_sync_markers(home_dir())) do
    if path_contains(current_path, marker) then
      return false
    end
  end

  return true
end

local function collect_paths()
  local home = home_dir()
  local paths = {}

  if is_windows then
    if home then
      vim.list_extend(paths, {
        vim.fs.joinpath(home, '.cargo', 'bin'),
        vim.fs.joinpath(home, '.bun', 'bin'),
        vim.fs.joinpath(home, '.local', 'bin'),
        vim.fs.joinpath(home, '.nimble', 'bin'),
        vim.fs.joinpath(home, 'scoop', 'shims'),
        vim.fs.joinpath(home, '.pyenv', 'pyenv-win', 'bin'),
        vim.fs.joinpath(home, '.pyenv', 'pyenv-win', 'shims'),
      })
    end

    if vim.env.ProgramData then
      table.insert(paths, vim.fs.joinpath(vim.env.ProgramData, 'chocolatey', 'bin'))
    end

    return paths
  end

  vim.list_extend(paths, {
    '/opt/homebrew/bin',
    '/opt/homebrew/sbin',
    '/usr/local/bin',
    '/usr/local/sbin',
  })

  if not home then
    return paths
  end

  local goenv_root = vim.fs.joinpath(home, '.goenv')
  local pyenv_root = vim.fs.joinpath(home, '.pyenv')
  local rbenv_root = vim.fs.joinpath(home, '.rbenv')

  if is_dir(goenv_root) then
    vim.env.GOENV_ROOT = goenv_root
    table.insert(paths, vim.fs.joinpath(goenv_root, 'shims'))
    table.insert(paths, vim.fs.joinpath(goenv_root, 'bin'))
  end

  if is_dir(pyenv_root) then
    vim.env.PYENV_ROOT = pyenv_root
    table.insert(paths, vim.fs.joinpath(pyenv_root, 'shims'))
    table.insert(paths, vim.fs.joinpath(pyenv_root, 'bin'))
  end

  if is_dir(rbenv_root) then
    vim.env.RBENV_ROOT = rbenv_root
    table.insert(paths, vim.fs.joinpath(rbenv_root, 'shims'))
    table.insert(paths, vim.fs.joinpath(rbenv_root, 'bin'))
  end

  vim.list_extend(paths, {
    vim.fs.joinpath(home, '.cargo', 'bin'),
    vim.fs.joinpath(home, '.bun', 'bin'),
    vim.fs.joinpath(home, '.nimble', 'bin'),
    vim.fs.joinpath(home, '.local', 'bin'),
  })

  return paths
end

function M.setup()
  if should_sync_path_from_shell() then
    local shell_path = read_login_shell_path()
    if shell_path then
      vim.env.PATH = shell_path
    end
  end

  prepend_existing_paths(collect_paths())
end

return M
