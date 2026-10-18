return {
  'pablopunk/pi.nvim',
  cmd = { 'PiAsk', 'PiAskSelection', 'PiCancel', 'PiToggleSession', 'PiLog', 'PiResponse' },
  keys = {
    { '<leader>ai', '<cmd>PiAsk<cr>', desc = 'Ask pi' },
    { '<leader>ai', ':PiAskSelection<cr>', mode = 'x', desc = 'Ask pi (selection)' },
    { '<leader>ac', '<cmd>PiCancel<cr>', desc = 'Cancel pi request' },
    { '<leader>al', '<cmd>PiLog<cr>', desc = 'Show pi log' },
    { '<leader>ar', '<cmd>PiResponse<cr>', desc = 'Show pi response' },
  },
  -- Use the provider/model and authentication already configured in the pi CLI.
  opts = {},
  config = function(_, opts)
    require('custom.pi').setup(opts)
  end,
}
