return {
  {
    dir = vim.fn.stdpath 'config',
    name = 'custom-treesitter-compat',
    lazy = false,
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    config = function()
      local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
      if not ok or type(parsers.ft_to_lang) == 'function' then
        return
      end

      parsers.ft_to_lang = function(ft)
        if vim.treesitter.language and type(vim.treesitter.language.get_lang) == 'function' then
          return vim.treesitter.language.get_lang(ft) or ft
        end
        return ft
      end

      parsers.get_parser = function(bufnr, lang)
        return vim.treesitter.get_parser(bufnr, lang)
      end
    end,
  },
}
