local M = {}

function M.setup()
  require('custom.bootstrap.path').setup()
  -- Keep local help searchable without tracking generated doc/tags.
  vim.cmd('silent! helptags ' .. vim.fn.fnameescape(vim.fn.stdpath 'config' .. '/doc'))
end

return M
