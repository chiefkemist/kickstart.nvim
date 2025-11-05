-- ECA (Editor Code Assistant) plugin configuration
-- Provides AI-powered coding assistance directly in Neovim
return {
  'editor-code-assistant/eca-nvim',
  dependencies = {
    'MunifTanjim/nui.nvim', -- Required: UI framework
    'nvim-lua/plenary.nvim', -- Optional: Enhanced async operations
  },
  keys = {
    { '<leader>ec', '<cmd>EcaChat<cr>', desc = '[E]CA [C]hat' },
    { '<leader>ef', '<cmd>EcaAddFile<cr>', desc = '[E]CA Add [F]ile' },
    { '<leader>ed', '<cmd>EcaAddDirectory<cr>', desc = '[E]CA Add [D]irectory' },
    { '<leader>es', '<cmd>EcaAddSelection<cr>', desc = '[E]CA Add [S]election', mode = 'v' },
    { '<leader>er', '<cmd>EcaServerRestart<cr>', desc = '[E]CA Server [R]estart' },
    { '<leader>et', '<cmd>EcaServerStatus<cr>', desc = '[E]CA Server S[t]atus' },
  },
  opts = {
    -- Enable debug mode for troubleshooting (set to true if you encounter issues)
    debug = false,

    -- Custom server arguments (optional)
    server_args = '',

    -- Keybindings for the chat interface
    keymaps = {
      chat = {
        send = '<C-s>', -- Send message (default: Ctrl+S)
        new_line = '<CR>', -- New line in message (default: Enter)
      },
    },
  },
  config = function(_, opts)
    require('eca').setup(opts)
  end,
}
