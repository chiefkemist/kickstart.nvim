local vscode = require 'vscode'

vim.opt.breakindent = true
vim.opt.hlsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.timeoutlen = 1000
vim.opt.updatetime = 250
vim.opt.scrolloff = 0

local function action(command, opts)
  return function()
    vscode.action(command, opts)
  end
end

local function map(mode, lhs, command, desc, action_opts, keymap_opts)
  local opts = vim.tbl_extend('force', {
    desc = desc,
    silent = true,
  }, keymap_opts or {})

  vim.keymap.set(mode, lhs, action(command, action_opts), opts)
end

local function map_callback(mode, lhs, callback, desc, keymap_opts)
  local opts = vim.tbl_extend('force', {
    desc = desc,
    silent = true,
  }, keymap_opts or {})

  vim.keymap.set(mode, lhs, callback, opts)
end

local function add_plugin_to_runtimepath(name)
  local path = vim.fn.stdpath 'data' .. '/lazy/' .. name
  if vim.uv.fs_stat(path) then
    vim.opt.runtimepath:append(path)
    return true
  end
  return false
end

-- These plugins only edit text. Loading them here preserves the same mini.ai and
-- mini.surround mappings without loading the normal NeoVim plugin stack.
if add_plugin_to_runtimepath 'mini.nvim' then
  local ok_ai, mini_ai = pcall(require, 'mini.ai')
  if ok_ai then
    mini_ai.setup { n_lines = 500 }
  end

  local ok_surround, mini_surround = pcall(require, 'mini.surround')
  if ok_surround then
    mini_surround.setup()
  end
end

-- Preserve the exact structural-editing and text-object behavior configured for
-- Clojure, Lisp, Scheme, and Fennel without loading the normal plugin stack.
if add_plugin_to_runtimepath 'vim-sexp' then
  vim.cmd 'runtime plugin/sexp.vim'
end
if add_plugin_to_runtimepath 'vim-sexp-mappings-for-regular-people' then
  vim.cmd 'runtime plugin/sexp_mappings_for_regular_people.vim'
end

-- Use vscode-neovim's range-aware comment operator for gc/gcc.
vim.cmd 'runtime vscode/code_actions.lua'

local block_comment = vscode.to_op(function(context)
  vscode.action('editor.action.blockComment', { range = context.range })
end)

vim.keymap.set({ 'n', 'x' }, 'gb', block_comment, {
  desc = 'Comment toggle blockwise',
  expr = true,
  silent = true,
})
vim.keymap.set('n', 'gbc', function()
  return block_comment() .. '_'
end, {
  desc = 'Comment toggle current block',
  expr = true,
  silent = true,
})

local function start_insert_at_comment()
  vim.cmd.startinsert { bang = true }
end

local function insert_comment_line(command)
  vscode.action(command, {
    callback = function(err)
      if err then
        return
      end
      vscode.action('editor.action.commentLine', { callback = start_insert_at_comment })
    end,
  })
end

map_callback('n', 'gco', function()
  insert_comment_line 'editor.action.insertLineAfter'
end, 'Add comment below')

map_callback('n', 'gcO', function()
  insert_comment_line 'editor.action.insertLineBefore'
end, 'Add comment above')

map_callback('n', 'gcA', function()
  vscode.eval_async(
    [[
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;

      const originalLine = editor.selection.active.line;
      const originalLength = editor.document.lineAt(originalLine).text.length;
      await vscode.commands.executeCommand('editor.action.insertLineAfter');
      await vscode.commands.executeCommand('editor.action.commentLine');

      const commentLine = editor.selection.active.line;
      const commentPosition = editor.selection.active.character;
      const commentText = editor.document.lineAt(commentLine).text;
      const replacement = ` ${commentText}\n`;
      const start = new vscode.Position(originalLine, originalLength);
      const end = editor.document.lineAt(commentLine).rangeIncludingLineBreak.end;
      await editor.edit(edit => edit.replace(new vscode.Range(start, end), replacement));

      const position = new vscode.Position(originalLine, originalLength + 1 + commentPosition);
      editor.selection = new vscode.Selection(position, position);
      editor.revealRange(new vscode.Range(position, position));
    ]],
    { callback = start_insert_at_comment }
  )
end, 'Add comment at end of line')

vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>', { silent = true })
vim.keymap.set('n', '+', '<C-a>', { desc = 'Increment', noremap = true })
vim.keymap.set('n', '-', '<C-x>', { desc = 'Decrement', noremap = true })

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking',
  group = vim.api.nvim_create_augroup('cursor-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Motions that need Cursor to move its viewport as well as NeoVim's cursor.
map_callback('n', 'gg', function()
  if vim.v.count > 0 then
    vim.cmd.normal {
      args = { tostring(vim.v.count) .. 'gg' },
      bang = true,
    }
  else
    vscode.action 'cursorTop'
  end
end, 'Go to first line')

map_callback('n', 'G', function()
  if vim.v.count > 0 then
    vim.cmd.normal {
      args = { tostring(vim.v.count) .. 'G' },
      bang = true,
    }
  else
    vscode.action 'cursorBottom'
  end
end, 'Go to last line')

-- Windows, editor groups, panels, and navigation history.
local directions = {
  h = 'Left',
  j = 'Down',
  k = 'Up',
  l = 'Right',
}

for key, direction in pairs(directions) do
  local command = 'workbench.action.navigate' .. direction
  local desc = 'Move focus ' .. direction:lower()

  map('n', '<C-' .. key .. '>', command, desc)
  map({ 'n', 'x' }, '<C-w>' .. key, command, desc)
  map({ 'n', 'x' }, '<C-w><C-' .. key .. '>', command, desc)
end

map('n', '<C-w>w', 'workbench.action.focusNextPart', 'Focus next window')
map('n', '<C-w><C-w>', 'workbench.action.focusNextPart', 'Focus next window')
map('n', '<C-w>p', 'workbench.action.focusPreviousPart', 'Focus previous window')
map('n', '<C-w>s', 'workbench.action.splitEditorDown', 'Split below')
map('n', '<C-w>v', 'workbench.action.splitEditorRight', 'Split right')
map('n', '<C-w>q', 'workbench.action.closeEditorsAndGroup', 'Close window')
map('n', '<C-w>c', 'workbench.action.closeEditorsAndGroup', 'Close window')
map('n', '<C-w>o', 'workbench.action.joinAllGroups', 'Keep only current window')
map('n', '<C-w>=', 'workbench.action.evenEditorWidths', 'Equalize windows')
map('n', '<C-w>_', 'workbench.action.toggleEditorWidths', 'Maximize window')
map('n', '<C-w>+', 'workbench.action.increaseViewHeight', 'Increase window height')
map('n', '<C-w>-', 'workbench.action.decreaseViewHeight', 'Decrease window height')
map('n', '<C-w>>', 'workbench.action.increaseViewWidth', 'Increase window width')
map('n', '<C-w><', 'workbench.action.decreaseViewWidth', 'Decrease window width')
map('n', '<C-w>H', 'workbench.action.moveActiveEditorGroupLeft', 'Move window left')
map('n', '<C-w>J', 'workbench.action.moveActiveEditorGroupDown', 'Move window down')
map('n', '<C-w>K', 'workbench.action.moveActiveEditorGroupUp', 'Move window up')
map('n', '<C-w>L', 'workbench.action.moveActiveEditorGroupRight', 'Move window right')
map('n', '<C-w>t', 'workbench.action.focusFirstEditorGroup', 'Focus first window')
map('n', '<C-w>b', 'workbench.action.focusLastEditorGroup', 'Focus last window')

map('n', '<C-o>', 'workbench.action.navigateBack', 'Jump back')
map('n', '<C-t>', 'workbench.action.navigateBack', 'Jump back from definition')
map('n', '<C-i>', 'workbench.action.navigateForward', 'Jump forward')

map('n', '[b', 'workbench.action.previousEditor', 'Previous buffer')
map('n', ']b', 'workbench.action.nextEditor', 'Next buffer')
map('n', '[B', 'workbench.action.firstEditorInGroup', 'First buffer')
map('n', ']B', 'workbench.action.lastEditorInGroup', 'Last buffer')

-- Diagnostics.
map('n', '[d', 'editor.action.marker.prev', 'Previous diagnostic')
map('n', ']d', 'editor.action.marker.next', 'Next diagnostic')
map('n', '[q', 'editor.action.marker.prev', 'Previous problem')
map('n', ']q', 'editor.action.marker.next', 'Next problem')

local function diagnostic_endpoint(first)
  vscode.eval_async(
    [[
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;

      const diagnostics = vscode.languages.getDiagnostics(editor.document.uri)
        .slice()
        .sort((left, right) => left.range.start.compareTo(right.range.start));
      if (!diagnostics.length) return;

      const diagnostic = args.first ? diagnostics[0] : diagnostics[diagnostics.length - 1];
      const position = diagnostic.range.start;
      editor.selection = new vscode.Selection(position, position);
      editor.revealRange(diagnostic.range, vscode.TextEditorRevealType.InCenter);
    ]],
    { args = { first = first } }
  )
end

map_callback('n', '[D', function()
  diagnostic_endpoint(true)
end, 'First diagnostic')
map_callback('n', ']D', function()
  diagnostic_endpoint(false)
end, 'Last diagnostic')
map('n', '<C-w>d', 'editor.action.showHover', 'Show diagnostic')
map('n', '<C-w><C-d>', 'editor.action.showHover', 'Show diagnostic')
map('n', '<leader>e', 'editor.action.showHover', 'Show diagnostic')
map('n', '<leader>q', 'workbench.actions.view.problems', 'Open problems')

-- Git hunk navigation, actions, diffs, and blame from gitsigns.nvim.
map('n', ']c', 'editor.action.dirtydiff.next', 'Next git change')
map('n', '[c', 'editor.action.dirtydiff.previous', 'Previous git change')
map('n', '<leader>hs', 'git.diff.stageHunk', 'Git: Stage hunk')
map('x', '<leader>hs', 'git.stageSelectedRanges', 'Git: Stage selected hunk')
map('n', '<leader>hr', 'git.revertChange', 'Git: Reset hunk')
map('x', '<leader>hr', 'git.revertSelectedRanges', 'Git: Reset selected hunk')
map('n', '<leader>hS', 'git.stageFile', 'Git: Stage buffer')
map('n', '<leader>hR', 'git.clean', 'Git: Reset buffer')
map('n', '<leader>hp', 'editor.action.dirtydiff.next', 'Git: Preview hunk')
map('n', '<leader>hi', 'gitlens.toggleFileChanges', 'Git: Preview inline changes')
map('n', '<leader>hb', 'gitlens.showQuickCommitFileDetails', 'Git: Blame line')
map('n', '<leader>hd', 'git.openChange', 'Git: Diff against index')
map('n', '<leader>hD', 'gitlens.diffWithPrevious', 'Git: Diff against last commit')
map('n', '<leader>hQ', 'git.openAllChanges', 'Git: All repository changes')
map('n', '<leader>hq', 'workbench.view.scm', 'Git: Current repository changes')
map('n', '<leader>tb', 'gitlens.toggleLineBlame', 'Toggle git line blame')
map('n', '<leader>tw', 'gitlens.toggleFileChanges', 'Toggle git word/file diff')

-- File navigation and Telescope equivalents.
map('n', '\\', 'workbench.files.action.showActiveFileInExplorer', 'Reveal current file')
map('n', '<leader>fe', 'workbench.view.explorer', 'Open file explorer')
map('n', '<leader>sf', 'workbench.action.quickOpen', 'Search files')
map('n', '<leader>sg', 'workbench.action.findInFiles', 'Search by grep')
map('n', '<leader>sd', 'workbench.actions.view.problems', 'Search diagnostics')
map('n', '<leader>sk', 'workbench.action.openGlobalKeybindings', 'Search keymaps')
map('n', '<leader>ss', 'workbench.action.showCommands', 'Search commands')
map('n', '<leader>sr', 'workbench.action.quickOpenPreviousRecentlyUsedEditor', 'Resume recent editor')
map('n', '<leader>s.', 'workbench.action.openRecent', 'Search recent files')
map('n', '<leader><leader>', 'workbench.action.showAllEditorsByMostRecentlyUsed', 'Find open editors')
map('n', '<leader>/', 'actions.find', 'Search current file')
map('n', 'gx', 'editor.action.openLink', 'Open link under cursor')

map_callback('n', '<leader>sh', function()
  vscode.eval_async(
    [[
      const docRoot = vscode.Uri.file(args.docRoot);
      const tagsUri = vscode.Uri.joinPath(docRoot, 'tags');
      const contents = new TextDecoder().decode(await vscode.workspace.fs.readFile(tagsUri));
      const tags = contents.split(/\r?\n/).filter(Boolean).map(line => {
        const [tag, file] = line.split('\t');
        return { label: tag, description: file, file };
      });

      const item = await vscode.window.showQuickPick(tags, {
        matchOnDescription: true,
        placeHolder: 'Search NeoVim help tags'
      });
      if (!item) return;

      const uri = vscode.Uri.joinPath(docRoot, item.file);
      const document = await vscode.workspace.openTextDocument(uri);
      const editor = await vscode.window.showTextDocument(document);
      const offset = document.getText().indexOf(`*${item.label}*`);
      const position = document.positionAt(Math.max(offset, 0));
      editor.selection = new vscode.Selection(position, position);
      editor.revealRange(new vscode.Range(position, position), vscode.TextEditorRevealType.InCenter);
    ]],
    { args = { docRoot = vim.env.VIMRUNTIME .. '/doc' } }
  )
end, 'Search NeoVim help')

map_callback('n', '<leader>sw', function()
  vscode.action('workbench.action.findInFiles', {
    args = { query = vim.fn.expand '<cword>' },
  })
end, 'Search current word')

map_callback('n', '<leader>s/', function()
  vscode.eval_async [[
    const query = await vscode.window.showInputBox({
      prompt: 'Search open files',
      placeHolder: 'Text to search for'
    });
    if (!query) return;

    const smartCase = /[A-Z]/.test(query);
    const needle = smartCase ? query : query.toLowerCase();
    const matches = [];

    for (const document of vscode.workspace.textDocuments) {
      if (document.uri.scheme !== 'file') continue;
      const lines = document.getText().split(/\r?\n/);
      for (let line = 0; line < lines.length; line++) {
        const haystack = smartCase ? lines[line] : lines[line].toLowerCase();
        const character = haystack.indexOf(needle);
        if (character !== -1) {
          matches.push({
            label: lines[line].trim() || '(blank line)',
            description: `${vscode.workspace.asRelativePath(document.uri)}:${line + 1}`,
            uri: document.uri.toString(),
            line,
            character
          });
        }
      }
    }

    const item = await vscode.window.showQuickPick(matches, {
      matchOnDescription: true,
      placeHolder: `${matches.length} matches in open files`
    });
    if (!item) return;

    const document = await vscode.workspace.openTextDocument(vscode.Uri.parse(item.uri));
    const editor = await vscode.window.showTextDocument(document);
    const position = new vscode.Position(item.line, item.character);
    editor.selection = new vscode.Selection(position, position);
    editor.revealRange(new vscode.Range(position, position), vscode.TextEditorRevealType.InCenter);
  ]]
end, 'Search open files')

map_callback('n', '<leader>sn', function()
  vscode.eval_async(
    [[
      const root = vscode.Uri.file(args.root);
      const files = [];

      async function walk(directory, prefix = '') {
        for (const [name, type] of await vscode.workspace.fs.readDirectory(directory)) {
          if (name === '.git') continue;
          const uri = vscode.Uri.joinPath(directory, name);
          const relative = prefix ? `${prefix}/${name}` : name;
          if (type === vscode.FileType.Directory) {
            await walk(uri, relative);
          } else {
            files.push({ label: relative, uri: uri.toString() });
          }
        }
      }

      await walk(root);
      const item = await vscode.window.showQuickPick(files, {
        matchOnDescription: true,
        placeHolder: 'Search NeoVim configuration files'
      });
      if (item) {
        await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(vscode.Uri.parse(item.uri)));
      }
    ]],
    { args = { root = vim.fn.stdpath 'config' } }
  )
end, 'Search NeoVim files')

-- LSP navigation. This includes both the custom mappings and NeoVim 0.12's
-- built-in LSP mappings, which otherwise call the embedded client with no server.
local lsp_maps = {
  { 'gd', 'editor.action.revealDefinition', 'Go to definition' },
  { 'gr', 'editor.action.goToReferences', 'Go to references' },
  { 'gI', 'editor.action.goToImplementation', 'Go to implementation' },
  { 'gD', 'editor.action.revealDeclaration', 'Go to declaration' },
  { 'grr', 'editor.action.goToReferences', 'Go to references' },
  { 'gri', 'editor.action.goToImplementation', 'Go to implementation' },
  { 'grt', 'editor.action.goToTypeDefinition', 'Go to type definition' },
  { 'grn', 'editor.action.rename', 'Rename symbol' },
  { 'gO', 'workbench.action.gotoSymbol', 'Document symbols' },
  { '<leader>D', 'editor.action.goToTypeDefinition', 'Go to type definition' },
  { '<leader>ds', 'workbench.action.gotoSymbol', 'Document symbols' },
  { '<leader>ws', 'workbench.action.showAllSymbols', 'Workspace symbols' },
  { '<leader>rn', 'editor.action.rename', 'Rename symbol' },
  { '<leader>ca', 'editor.action.quickFix', 'Code action' },
  { '<leader>ld', 'editor.action.revealDefinition', 'Direct definition' },
  { '<leader>lr', 'editor.action.goToReferences', 'Direct references' },
  { '<leader>cc', 'editor.action.quickFix', 'Code actions' },
  { '<leader>cr', 'editor.action.rename', 'Rename symbol' },
  { '<leader>cf', 'editor.action.formatDocument', 'Format document' },
  { '<leader>cR', 'editor.action.goToReferences', 'Find all references' },
}

for _, mapping in ipairs(lsp_maps) do
  map('n', mapping[1], mapping[2], mapping[3])
end

map('n', 'K', 'editor.action.showHover', 'Hover documentation')
map('n', 'gK', 'editor.action.triggerParameterHints', 'Signature help')
map({ 'n', 'x' }, 'gra', 'editor.action.quickFix', 'Code action')
map('n', 'grx', 'codelens.showLensesInCurrentLine', 'Run code lens')

-- Completion and snippets from the original nvim-cmp/LuaSnip configuration.
map('i', '<C-n>', 'selectNextSuggestion', 'Select next completion')
map('i', '<C-p>', 'selectPrevSuggestion', 'Select previous completion')
map('i', '<C-y>', 'acceptSelectedSuggestion', 'Accept completion')
map('i', '<C-Space>', 'editor.action.triggerSuggest', 'Show completions')
map('i', '<C-l>', 'jumpToNextSnippetPlaceholder', 'Next snippet placeholder')
map('i', '<C-h>', 'jumpToPrevSnippetPlaceholder', 'Previous snippet placeholder')
map('i', '<C-s>', 'editor.action.triggerParameterHints', 'Signature help')
map('i', '<C-k>', 'editor.action.triggerParameterHints', 'Signature help')

-- Terminal.
map('n', '<leader>tt', 'workbench.action.terminal.toggleTerminal', 'Toggle terminal')

local function terminal_send(name, cwd, command)
  vscode.eval_async(
    [[
      let terminal = vscode.window.terminals.find(terminal => terminal.name === args.name);
      if (!terminal) {
        terminal = vscode.window.createTerminal({ name: args.name, cwd: args.cwd });
      }
      terminal.show(false);
      if (args.command) terminal.sendText(args.command, true);
    ]],
    { args = { name = name, cwd = cwd, command = command } }
  )
end

local function project_root(bufnr, marker)
  local file = vim.api.nvim_buf_get_name(bufnr)
  return vim.fs.root(file, marker) or vim.fs.dirname(file)
end

local elixir_repl_modes = {}

local function elixir_terminal_name(root, mode)
  return 'IEx ' .. mode .. ' (' .. vim.fs.basename(root) .. ')'
end

local function terminal_exists(name)
  return vscode.eval('return vscode.window.terminals.some(terminal => terminal.name === args.name)', {
    args = { name = name },
  })
end

local function elixir_repl(bufnr, requested_mode)
  local root = project_root(bufnr, 'mix.exs')
  local has_mix = vim.uv.fs_stat(root .. '/mix.exs') ~= nil
  local mode = requested_mode or elixir_repl_modes[root] or (has_mix and 'mix' or 'plain')

  if (mode == 'mix' or mode == 'phoenix') and not has_mix then
    mode = 'plain'
  end

  elixir_repl_modes[root] = mode
  local commands = {
    plain = 'iex',
    mix = 'iex -S mix',
    phoenix = 'iex -S mix phx.server',
  }
  local name = elixir_terminal_name(root, mode)
  terminal_send(name, root, terminal_exists(name) and nil or commands[mode])
end

local function visual_text(bufnr)
  local start_pos = vim.fn.getpos 'v'
  local end_pos = vim.api.nvim_win_get_cursor(0)
  local start_row = start_pos[2] - 1
  local start_col = math.max(start_pos[3] - 1, 0)
  local end_row = end_pos[1] - 1
  local end_col = end_pos[2]

  if end_row < start_row or (end_row == start_row and end_col < start_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  if vim.fn.mode() ~= 'V' and #lines > 0 then
    lines[1] = lines[1]:sub(start_col + 1)
    lines[#lines] = lines[#lines]:sub(1, end_col + 1)
  end
  return table.concat(lines, '\n')
end

local function elixir_eval(bufnr, text)
  if not text or text == '' then
    return
  end

  local root = project_root(bufnr, 'mix.exs')
  local mode = elixir_repl_modes[root] or (vim.uv.fs_stat(root .. '/mix.exs') and 'mix' or 'plain')
  local path = vim.fn.tempname() .. '.exs'
  vim.fn.writefile(vim.split(text, '\n', { plain = true }), path)
  local name = elixir_terminal_name(root, mode)
  local command = 'Code.eval_file(' .. string.format('%q', path) .. ')'

  if terminal_exists(name) then
    terminal_send(name, root, command)
  else
    elixir_repl(bufnr, mode)
    vim.defer_fn(function()
      terminal_send(name, root, command)
    end, 1200)
  end
  elixir_repl_modes[root] = mode
end

local function nim_command(bufnr, kind)
  local file = vim.api.nvim_buf_get_name(bufnr)
  local root = project_root(bufnr, function(name)
    return name:match '%.nimble$' ~= nil
  end)
  local nimble = vim.fs.find(function(name)
    return name:match '%.nimble$' ~= nil
  end, { path = root, type = 'file', limit = 1 })[1]
  local commands

  if nimble then
    commands = {
      build = 'nimble build --backend:c',
      run = 'nimble run --backend:c',
      check = 'nim check --backend:c ' .. vim.fn.shellescape(file),
      test = 'nimble test --backend:c',
    }
  else
    commands = {
      build = 'nim c ' .. vim.fn.shellescape(file),
      run = 'nim c -r ' .. vim.fn.shellescape(file),
      check = 'nim check --backend:c ' .. vim.fn.shellescape(file),
    }
  end

  if commands[kind] then
    terminal_send('Nim (' .. vim.fs.basename(root) .. ')', root, commands[kind])
  end
end

local function setup_language_keymaps(bufnr)
  local filetype = vim.bo[bufnr].filetype
  local opts = { buffer = bufnr }

  if vim.tbl_contains({ 'elixir', 'eelixir', 'heex', 'surface' }, filetype) then
    map_callback('n', '<localleader>ro', function()
      elixir_repl(bufnr)
    end, 'Elixir: Open default REPL', opts)
    map_callback('n', '<localleader>ri', function()
      elixir_repl(bufnr, 'plain')
    end, 'Elixir: Open plain IEx', opts)
    map_callback('n', '<localleader>rm', function()
      elixir_repl(bufnr, 'mix')
    end, 'Elixir: Open IEx -S mix', opts)
    map_callback('n', '<localleader>rp', function()
      elixir_repl(bufnr, 'phoenix')
    end, 'Elixir: Open Phoenix IEx', opts)
    map_callback('n', '<localleader>rl', function()
      elixir_eval(bufnr, vim.api.nvim_get_current_line())
    end, 'Elixir: Evaluate line', opts)
    map_callback('n', '<localleader>rb', function()
      elixir_eval(bufnr, table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n'))
    end, 'Elixir: Evaluate buffer', opts)
    map_callback('x', '<localleader>re', function()
      elixir_eval(bufnr, visual_text(bufnr))
    end, 'Elixir: Evaluate selection', opts)
    map('n', '<localleader>rc', 'workbench.action.terminal.clear', 'Elixir: Clear REPL', nil, opts)
  elseif filetype == 'nim' then
    for key, kind in pairs { b = 'build', r = 'run', c = 'check', t = 'test' } do
      map_callback('n', '<leader>n' .. key, function()
        nim_command(bufnr, kind)
      end, 'Nim: ' .. kind, opts)
    end
  elseif filetype == 'clojure' then
    local clojure_maps = {
      { '<leader>car', 'calva.jackIn', 'Clojure: Start or restart REPL' },
      { '<leader>cd', 'calva.disconnect', 'Clojure: Disconnect REPL' },
      { '<leader>ct', 'editor.action.refactor', 'Clojure: Cycle collection/refactor' },
      { '<leader>e!', 'calva.evaluateSelectionReplace', 'Clojure: Evaluate and replace' },
      { '<leader>eb', 'calva.loadFile', 'Clojure: Evaluate buffer' },
      { '<leader>ece', 'calva.evaluateSelectionAsComment', 'Clojure: Evaluate form as comment' },
      { '<leader>ecr', 'calva.evaluateTopLevelFormAsComment', 'Clojure: Evaluate root form as comment' },
      { '<leader>ee', 'calva.evaluateSelection', 'Clojure: Evaluate form or selection' },
      { '<leader>ef', 'calva.loadFile', 'Clojure: Evaluate file' },
      { '<leader>ei', 'calva.interruptAllEvaluations', 'Clojure: Interrupt evaluation' },
      { '<leader>ep', 'calva.evaluateSelection', 'Clojure: Repeat/evaluate current form' },
      { '<leader>er', 'calva.evaluateCurrentTopLevelForm', 'Clojure: Evaluate root form' },
      { '<leader>ew', 'calva.evaluateSelection', 'Clojure: Evaluate word/form' },
      { '<leader>lR', 'calva.clearReplHistory', 'Clojure: Clear REPL log' },
      { '<leader>le', 'calva.showReplWindow', 'Clojure: Open REPL log' },
      { '<leader>lg', 'calva.showReplWindow', 'Clojure: Toggle REPL log' },
      { '<leader>ll', 'calva.showReplWindow', 'Clojure: Jump to REPL log' },
      { '<leader>lq', 'workbench.action.closePanel', 'Clojure: Close REPL panel' },
      { '<leader>ra', 'calva.loadFile', 'Clojure: Refresh namespaces' },
      { '<leader>rc', 'calva.clearInlineResults', 'Clojure: Clear evaluation results' },
      { '<leader>rr', 'calva.loadFile', 'Clojure: Refresh changed namespace' },
      { '<leader>sQ', 'calva.disconnect', 'Clojure: Close all REPL sessions' },
      { '<leader>sc', 'calva.connect', 'Clojure: Connect to REPL' },
      { '<leader>sf', 'calva.jackIn', 'Clojure: Start fresh REPL' },
      { '<leader>sl', 'calva.showReplSessionsMenu', 'Clojure: List REPL sessions' },
      { '<leader>sn', 'calva.showReplSessionsMenu', 'Clojure: Select next REPL session' },
      { '<leader>sp', 'calva.showReplSessionsMenu', 'Clojure: Select previous REPL session' },
      { '<leader>sq', 'calva.disconnect', 'Clojure: Close REPL session' },
      { '<leader>ss', 'calva.showReplSessionsMenu', 'Clojure: Select REPL session' },
      { '<leader>tN', 'calva.runNamespaceTests', 'Clojure: Run namespace test variant' },
      { '<leader>ta', 'calva.runAllTests', 'Clojure: Run all tests' },
      { '<leader>tc', 'calva.runTestUnderCursor', 'Clojure: Run test under cursor' },
      { '<leader>tn', 'calva.runNamespaceTests', 'Clojure: Run namespace tests' },
      { '<leader>v1', 'calva.showReplWindow', 'Clojure: Show latest result' },
      { '<leader>v2', 'calva.showReplWindow', 'Clojure: Show previous result' },
      { '<leader>v3', 'calva.showReplWindow', 'Clojure: Show third result' },
      { '<leader>ve', 'calva.printLastStacktrace', 'Clojure: Show last exception' },
      { '<leader>vt', 'calva.revealInspector', 'Clojure: Show tapped values' },
    }

    for _, mapping in ipairs(clojure_maps) do
      map('n', mapping[1], mapping[2], mapping[3], nil, opts)
    end

    map('x', '<leader>ee', 'calva.evaluateSelection', 'Clojure: Evaluate selection', nil, opts)
  end
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('cursor-language-keymaps', { clear = true }),
  callback = function(args)
    setup_language_keymaps(args.buf)
  end,
})

vim.schedule(function()
  if vim.api.nvim_buf_is_valid(0) and vim.bo.filetype ~= '' then
    setup_language_keymaps(0)
  end
end)

-- Debugging.
map('n', '<F5>', 'workbench.action.debug.start', 'Debug: Start/Continue')
map('n', '<F1>', 'workbench.action.debug.stepInto', 'Debug: Step Into')
map('n', '<F2>', 'workbench.action.debug.stepOver', 'Debug: Step Over')
map('n', '<F3>', 'workbench.action.debug.stepOut', 'Debug: Step Out')
map('n', '<F7>', 'workbench.view.debug', 'Debug: Open view')
map('n', '<leader>b', 'editor.debug.action.toggleBreakpoint', 'Debug: Toggle Breakpoint')
map('n', '<leader>B', 'editor.debug.action.conditionalBreakpoint', 'Debug: Conditional Breakpoint')
