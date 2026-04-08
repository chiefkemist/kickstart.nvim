local M = {}

local function installed_parsers()
  local ok, treesitter = pcall(require, 'nvim-treesitter')
  if not ok or type(treesitter.get_installed) ~= 'function' then
    return {}
  end

  return treesitter.get_installed 'parsers'
end

function M.get_module(name)
  if name == 'highlight' then
    return {
      additional_vim_regex_highlighting = false,
    }
  end

  return {}
end

function M.is_enabled(name, lang)
  if name ~= 'highlight' then
    return false
  end

  if vim.treesitter.language and type(vim.treesitter.language.get_lang) == 'function' then
    lang = vim.treesitter.language.get_lang(lang) or lang
  end

  return vim.tbl_contains(installed_parsers(), lang)
end

return M
