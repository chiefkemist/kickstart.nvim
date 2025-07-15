return {
  {
    'github/copilot.vim', -- Github Copilot
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim", -- Github Copilot Chat
    dependencies = {
      { "github/copilot.vim" }, -- or zbirenbaum/copilot.lua
      { "nvim-lua/plenary.nvim", branch = "master" }, -- for curl, log and async functions
    },
    build = "make tiktoken", -- Only on MacOS or Linux
    opts = {
      -- See Configuration section for options
    },
    -- See Commands section for default commands if you want to lazy load on them
  },
  {
    'scrooloose/nerdtree', -- NERDTree
  },
  {
    'nvim-orgmode/orgmode',
    event = 'VeryLazy',
    ft = { 'org' },
    config = function()
      -- Setup orgmode
      require('orgmode').setup {
        org_agenda_files = '~/orgfiles/**/*',
        org_default_notes_file = '~/orgfiles/refile.org',
      }

      -- NOTE: If you are using nvim-treesitter with ~ensure_installed = "all"~ option
      -- add ~org~ to ignore_install
      -- require('nvim-treesitter.configs').setup({
      --   ensure_installed = 'all',
      --   ignore_install = { 'org' },
      -- })
    end,
  },
  {
    'NeogitOrg/neogit', -- Neogit
    dependencies = {
      'nvim-lua/plenary.nvim', -- required
      'sindrets/diffview.nvim', -- optional - Diff integration

      -- Only one of these is needed, not both.
      'nvim-telescope/telescope.nvim', -- optional
      'ibhagwan/fzf-lua', -- optional
    },
    config = true,
  },
  {
    'prabirshrestha/asyncomplete.vim', -- Asyncomplete Vim
  },
  {
    'prabirshrestha/async.vim', -- Async Vim
  },
  {
    'prabirshrestha/vim-lsp', -- Vim LSP
  },
  {
    'prabirshrestha/asyncomplete-lsp.vim', -- Asyncomplete LSP Vim
  },
}
