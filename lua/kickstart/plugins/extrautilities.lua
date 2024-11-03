return {
  {
    'github/copilot.vim', -- AI Copilot
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
