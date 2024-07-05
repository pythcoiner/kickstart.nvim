-- Increase message history size
-- increases the lines displayed w/ :messages
vim.o.history = 1000

-- Messages/logs verbosity
-- 1 = less, 15 = more
vim.o.verbose = 1

-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = true

-- [[ Setting options ]]
-- See `:help vim.opt`
-- NOTE: for more options, you can see `:help option-list`

-- Make line numbers default
vim.opt.number = true
vim.opt.relativenumber = true

-- Enable mouse mode, can be useful for resizing splits for example!
vim.opt.mouse = 'a'
-- Don't show the mode, since it's already in the status line
vim.opt.showmode = false

-- Sync clipboard between OS and Neovim.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.opt.clipboard = 'unnamedplus'

-- Enable break indent
vim.opt.breakindent = true

-- Save undo history
vim.opt.undofile = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Keep signcolumn on by default
vim.opt.signcolumn = 'yes'

-- Decrease update time
vim.opt.updatetime = 250

-- Decrease mapped sequence wait time
-- Displays which-key popup sooner
vim.opt.timeoutlen = 300

-- Configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live, as you type!
vim.opt.inccommand = 'split'

-- Show which line your cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 10

-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

-- Resize inner window
vim.keymap.set('n', '<C-Up>', ':resize +5<CR>', { desc = 'Resize window Up' })
vim.keymap.set('n', '<C-Down>', ':resize -5<CR>', { desc = 'Resize window Down' })
vim.keymap.set('n', '<C-Left>', ':vertical resize -5<CR>', { desc = 'Resize window Left' })
vim.keymap.set('n', '<C-Right>', ': vertical resize +5<CR>', { desc = 'Resize window Right' })

-- Set highlight on search, but clear on pressing <Esc> in normal mode
vim.opt.hlsearch = true
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous [D]iagnostic message' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next [D]iagnostic message' })
vim.keymap.set('n', '<leader>e', ':Telescope diagnostics<CR>', { desc = 'Show diagnostic [E]rror messages' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', 'H', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', 'L', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', 'J', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', 'K', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- New QFL

-- Add an entry to the QuickFixList
function AddCommentToQFList()
  -- Prompt the user to enter a comment
  local userComment = vim.fn.input 'Enter comment/info: '

  -- Check if the user entered a comment
  if userComment ~= '' then
    -- Define the quickfix entry
    local entry = { {
      filename = vim.fn.expand '%:p',
      lnum = vim.fn.line '.',
      col = vim.fn.col '.',
      text = userComment,
    } }

    -- Capture current buffer number before opening quickfix
    local current_buf = vim.api.nvim_get_current_buf()

    -- Add the entry to the quickfix list and append it
    vim.fn.setqflist(entry, 'a')

    -- Return to the original buffer
    vim.api.nvim_set_current_buf(current_buf)
    SaveTodo()
  end
end

-- Remove an entry from the QuickFixList
function RemoveQFEntry()
  local lnum = vim.fn.line '.'

  -- Get the current list of quickfix entries
  local qf_list = vim.fn.getqflist()

  -- Remove the entry at the given index (1-based indexing in Lua)
  table.remove(qf_list, lnum)

  -- Set the modified list back as the new quickfix list
  vim.fn.setqflist(qf_list, 'r')
  SaveTodo()
end

-- Check if we are at a repository root (contains a .git folder)
function RootIsGitRepo()
  local cwd = vim.fn.getcwd()
  local git_dir = cwd .. '/.git'
  if vim.fn.isdirectory(git_dir) == 0 then
    return false
  end
  return true
end

-- Add .todo to the excluded files
function MaybeExcludeTodo()
  local exclude = vim.fn.getcwd() .. '/.git/info/exclude'
  -- Read the content of the exclude file
  local lines = {}
  for line in io.lines(exclude) do
    table.insert(lines, line)
  end

  -- Check if the exclude file contains ".todo"
  for _, line in ipairs(lines) do
    if line == '.todo' then
      print '.todo is already in the exclude file.'
      return false
    end
  end

  -- Append ".todo" to the exclude file
  local file = io.open(exclude, 'a')
  if file then
    file:write '.todo\n'
    file:close()
    print '.todo added to the exclude file.'
    return true
  else
    print 'Error opening the exclude file for writing.'
    return false
  end
end

_G.todo = 0
function LoadTodo()
  local cwd = vim.fn.getcwd()
  local todo_file = cwd .. '/.todo'

  if _G.todo == 1 then
    vim.cmd 'copen' -- Open the quickfix window
    return
  end

  -- Check if the .todo file exists
  if vim.fn.filereadable(todo_file) == 0 then
    vim.fn.setqflist({}, 'r', { title = '.todo' })
    vim.cmd 'copen' -- Open the quickfix window
    print '.todo file does not exist.'
    return
  end

  -- Read the content of the .todo file
  local lines = {}
  for line in io.lines(todo_file) do
    local filename, lnum, col, text = string.match(line, '([^:]+):(%d+):(%d+):(.+)')
    table.insert(lines, {
      filename = filename,
      lnum = tonumber(lnum),
      col = tonumber(col),
      text = text,
    })
  end

  -- Load the lines into the quickfix list
  vim.fn.setqflist({}, 'r', { title = '.todo', items = lines })
  vim.cmd 'copen' -- Open the quickfix window
  _G.todo = 1
  print '.todo content has been loaded into the quickfix list.'
end

function SaveTodo()
  if RootIsGitRepo() then
    MaybeExcludeTodo()

    local cwd = vim.fn.getcwd()
    local todo_file = cwd .. '/.todo'

    -- Get the current quickfix list
    local quickfix_list = vim.fn.getqflist()

    -- Convert the quickfix list to a string
    local quickfix_content = ''
    for _, item in ipairs(quickfix_list) do
      local filename = vim.fn.bufname(item.bufnr)
      quickfix_content = quickfix_content .. string.format('%s:%d:%d:%s\n', filename, item.lnum, item.col, item.text)
    end

    -- Write the quickfix content to the .todo file
    local file = io.open(todo_file, 'w')
    if file then
      file:write(quickfix_content)
      file:close()
      print 'Todo saved!'
    else
      print 'Error opening .todo file for writing.'
    end
  else
    print 'Cannot save todo as the root is not a git repo'
  end
end

vim.keymap.set('n', '<leader>cx', AddCommentToQFList, { noremap = true, silent = true, desc = 'Add entry to QuickFixList' })
vim.keymap.set('n', '<leader>co', LoadTodo, { desc = 'Open QuickFixList' })
vim.keymap.set('n', '<leader>cd', RemoveQFEntry, { desc = 'Remove QuickFixList entry' })
vim.keymap.set('n', '<leader>cc', ':ccl<CR>', { desc = 'Close QuickFixList' })

-- Move between hunks
vim.keymap.set('n', '<C-l>', ':Gitsigns next_hunk<CR>', { desc = 'Next hunk' })
vim.keymap.set('n', '<C-h>', ':Gitsigns prev_hunk<CR>', { desc = 'Previous hunk' })

-- Page Up/Down
vim.keymap.set('n', '<C-j>', '<C-d>', { desc = 'Page Down' })
vim.keymap.set('n', '<C-k>', '<C-u>', { desc = 'Page Up' })

-- Quick Fix List feature
vim.keymap.set('n', '<leader>c<leader>', ':cnext', { desc = ' Next QFL element' })
vim.keymap.set('n', '<C-j>', '<C-d>', { desc = 'Page Down' })

-- Diagram mode

-- replace chars by spaces in visual selected mode
_G.ReplaceWithSpaces = function()
  if _G.diagram == 1 then
    -- Get the selected range
    local start_pos = vim.fn.getpos "'<"
    local end_pos = vim.fn.getpos "'>"

    -- Enter normal mode
    vim.api.nvim_command 'normal! \\<Esc>'

    -- Loop through each line in the selected range
    for line = start_pos[2], end_pos[2] do
      -- Get the column range
      local start_col = start_pos[3] - 1
      local end_col = end_pos[3] - 1

      -- Replace characters in the selected range with spaces
      for col = start_col, end_col do
        vim.api.nvim_buf_set_text(0, line - 1, col, line - 1, col + 1, { ' ' })
      end
    end
  end
end

_G.diagram = 0
function DiagramMode()
  if _G.diagram == 0 then
    _G.diagram = 1
    vim.opt.virtualedit = 'all'
    vim.opt.listchars = { tab = '» ', trail = ' ', nbsp = '␣' }
    require('ibl').update { enabled = false }

    -- draw a line on HJKL keystokes
    vim.api.nvim_buf_set_keymap(0, 'n', 'J', '<C-v>j:VBox<CR>', { noremap = true })
    vim.api.nvim_buf_set_keymap(0, 'n', 'K', '<C-v>k:VBox<CR>', { noremap = true })
    vim.api.nvim_buf_set_keymap(0, 'n', 'L', '<C-v>l:VBox<CR>', { noremap = true })
    vim.api.nvim_buf_set_keymap(0, 'n', 'H', '<C-v>h:VBox<CR>', { noremap = true })
    -- rebind 'x' -> overwrite w/ a space
    vim.api.nvim_buf_set_keymap(0, 'n', 'x', 'r <Esc>', { noremap = true })
    vim.keymap.set('x', 'd', ReplaceWithSpaces, { noremap = true })
    -- draw a box by pressing "f" with visual selection
    vim.api.nvim_buf_set_keymap(0, 'v', 'f', ':VBox<CR>', { noremap = true })
    vim.api.nvim_echo({ { 'Diagram mode enabled!', 'Normal' } }, false, {})
  else
    _G.diagram = 0
    vim.opt.virtualedit = ''
    vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
    require('ibl').update { enabled = true }

    vim.api.nvim_buf_del_keymap(0, 'n', 'J')
    vim.api.nvim_buf_del_keymap(0, 'n', 'K')
    vim.api.nvim_buf_del_keymap(0, 'n', 'L')
    vim.api.nvim_buf_del_keymap(0, 'n', 'H')
    vim.api.nvim_buf_del_keymap(0, 'n', 'x')
    vim.api.nvim_buf_del_keymap(0, 'v', 'f')
    vim.api.nvim_echo({ { 'Diagram mode disabled!', 'Normal' } }, false, {})
  end
end
vim.keymap.set('n', '<leader>dd', DiagramMode, { desc = 'Disable diagram mode' })

-- Map the function to a key combination in visual block mode
vim.api.nvim_set_keymap('x', '<Leader>r', ':lua ReplaceWithSpaces()<CR>', { noremap = true, silent = true })

-- Toggle file overview
vim.keymap.set('n', '<leader>ll', ':SymbolsOutline<CR>', { desc = 'File Overview' })

-- [[ NVimTree keymaps ]]
vim.api.nvim_set_keymap('n', '<leader>aa', ':NvimTreeToggle<CR>', { noremap = true, silent = true })

-- [[ Rust customs keymaps ]]
--
function _G.run_cargo_run()
  vim.cmd '!cargo run --release'
end

function _G.run_cargo_clippy()
  vim.cmd '!cargo clippy'
end
vim.api.nvim_set_keymap('n', '<leader>rc', ':lua run_cargo_clippy()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>rr', ':lua run_cargo_run()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>rf', ':RustFmt<CR>)', { noremap = true, silent = true })
-- [[ AutoSave feature ]]
-- Counter for auto-save events
Auto_save_counter = 0

-- Function to auto-save the buffer

function _G.auto_save()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].modifiable and not vim.bo[bufnr].readonly then
    vim.cmd 'silent! write'
  end
end

-- Function to handle auto-save with a counter
function _G.counted_auto_save()
  Auto_save_counter = Auto_save_counter + 1
  if Auto_save_counter >= 1 then
    auto_save()
    Auto_save_counter = 0
  end
end

-- Auto-save on InsertLeave and TextChanged events
vim.api.nvim_create_autocmd({ 'InsertLeave', 'TextChanged' }, {
  callback = counted_auto_save,
})

-- --: Auto-save on pressing Escape or Enter
-- vim.api.nvim_create_autocmd('BufEnter', {
--   callback = function()
--     vim.api.nvim_buf_set_keymap(0, 'i', '<Esc>', '<Esc>:lua auto_save()<CR>', { noremap = true, silent = true })
--   end,
-- })

-- [[ AutoRead feature ]]
-- Function to auto-read the buffer
function _G.auto_read()
  if vim.fn.getcmdwintype() == '' and vim.bo.modifiable then
    vim.cmd 'checktime'
  end
end

-- Auto-read on FocusGained and CursorHold events
vim.api.nvim_create_autocmd({ 'FocusGained', 'CursorHold' }, {
  callback = auto_read,
})

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank { timeout = 800 }
  end,
})

-- [[ Install `lazy.nvim` plugin manager ]]
--    See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- NOTE: Here is where you install your plugins.

require('lazy').setup({
  -- NOTE: Plugins can be added with a link (or for a github repo: 'owner/repo' link).
  'tpope/vim-sleuth', -- Detect tabstop and shiftwidth automatically

  -- Ascii diagram
  'pythcoiner/venn.nvim',

  -- Code structure overview
  {
    'simrat39/symbols-outline.nvim',
    config = function()
      require('symbols-outline').setup {
        highlight_hovered_item = true,
        show_guides = true,
        auto_preview = false,
        position = 'right',
        width = 25,
        auto_close = true,
        show_numbers = false,
        show_relative_numbers = false,
        show_symbol_details = true,
        preview_bg_highlight = 'Pmenu',
        keymaps = {
          close = { 'q' },
          goto_location = '<Cr>',
          focus_location = 'o',
          hover_symbol = '<C-space>',
          toggle_preview = 'K',
          rename_symbol = 'r',
          code_actions = 'a',
        },
        lsp_blacklist = {},
        symbol_blacklist = {},
        symbols = {
          File = { icon = '', hl = 'TSURI' },
          Module = { icon = '', hl = 'TSNamespace' },
          Namespace = { icon = '', hl = 'TSNamespace' },
          Package = { icon = '', hl = 'TSNamespace' },
          Class = { icon = '', hl = 'TSType' },
          Method = { icon = '', hl = 'TSMethod' },
          Property = { icon = '', hl = 'TSMethod' },
          Field = { icon = '', hl = 'TSField' },
          Constructor = { icon = '', hl = 'TSConstructor' },
          Enum = { icon = '', hl = 'TSType' },
          Interface = { icon = '', hl = 'TSType' },
          Function = { icon = '', hl = 'TSFunction' },
          Variable = { icon = '', hl = 'TSConstant' },
          Constant = { icon = 'C', hl = 'TSConstant' },
          String = { icon = 'S', hl = 'TSString' },
          Number = { icon = '', hl = 'TSNumber' },
          Boolean = { icon = '◩', hl = 'TSBoolean' },
          Array = { icon = '', hl = 'TSConstant' },
          Object = { icon = '', hl = 'TSType' },
          Key = { icon = 'K', hl = 'TSType' },
          Null = { icon = '-', hl = 'TSType' },
          EnumMember = { icon = '', hl = 'TSField' },
          Struct = { icon = '', hl = 'TSType' },
          Event = { icon = '', hl = 'TSType' },
          Operator = { icon = '+', hl = 'TSOperator' },
        },
      }
    end,
  },

  -- nvim-tree
  {
    'pythcoiner/nvim-tree.lua',
    requires = {
      'kyazdani42/nvim-web-devvicons',
    },
    config = function()
      require('nvim-tree').setup {}
      vim.cmd 'autocmd VimEnter * NvimTreeToggle'
    end,
  },

  -- Git integration
  'tpope/vim-fugitive',

  -- markdown tables
  'dhruvasagar/vim-table-mode',

  'rhysd/vim-grammarous', -- english grammar checker
  -- NOTE: Plugins can also be added by using a table,
  -- with the first argument being the link and the following
  -- keys can be used to configure plugin behavior/loading/etc.:/
  --
  -- "gc" to comment visual regions/lines
  { 'numToStr/Comment.nvim', opts = {} },

  -- Here is a more advanced example where we pass configuration
  -- options to `gitsigns.nvim`. This is equivalent to the following Lua:
  --    require('gitsigns').setup({ ... })
  --
  -- See `:help gitsigns` to understand what the configuration keys do
  { -- Adds git related signs to the gutter, as well as utilities for managing changes
    'lewis6991/gitsigns.nvim',
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
    },
  },

  -- NOTE: Plugins can also be configured to run Lua code when they are loaded.
  --
  -- This is often very useful to both group configuration, as well as handle
  -- lazy loading plugins that don't need to be loaded immediately at startup.
  --
  -- For example, in the following configuration, we use:
  --  event = 'VimEnter'
  --
  -- which loads which-key before all the UI elements are loaded. Events can be
  -- normal autocommands events (`:help autocmd-events`).
  --
  -- Then, because we use the `config` key, the configuration only runs
  -- after the plugin has been loaded:
  --  config = function() ... end

  { -- Useful plugin to show you pending keybinds.
    'folke/which-key.nvim',
    event = 'VimEnter', -- Sets the loading event to 'VimEnter'
    config = function() -- This is the function that runs, AFTER loading
      require('which-key').setup()

      -- Document existing key chains
      require('which-key').register {
        ['<leader>c'] = { name = '[C]ode', _ = 'which_key_ignore' },
        ['<leader>d'] = { name = '[D]ocument', _ = 'which_key_ignore' },
        ['<leader>r'] = { name = '[R]ename', _ = 'which_key_ignore' },
        ['<leader>s'] = { name = '[S]earch', _ = 'which_key_ignore' },
        ['<leader>w'] = { name = '[W]orkspace', _ = 'which_key_ignore' },
        ['<leader>t'] = { name = '[T]oggle', _ = 'which_key_ignore' },
        ['<leader>h'] = { name = 'Git [H]unk', _ = 'which_key_ignore' },
      }
      -- visual mode
      require('which-key').register({
        ['<leader>h'] = { 'Git [H]unk' },
      }, { mode = 'v' })
    end,
  },

  { -- Fuzzy Finder (files, lsp, etc)
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { -- If encountering errors, see telescope-fzf-native README for installation instructions
        'nvim-telescope/telescope-fzf-native.nvim',

        -- `build` is used to run some command when the plugin is installed/updated.
        -- This is only run then, not every time Neovim starts up.
        build = 'make',

        -- `cond` is a condition used to determine whether this plugin should be
        -- installed and loaded.
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
      { 'nvim-telescope/telescope-ui-select.nvim' },

      -- Useful for getting pretty icons, but requires a Nerd Font.
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()
      -- [[ Configure Telescope ]]
      -- See `:help telescope` and `:help telescope.setup()`
      require('telescope').setup {
        extensions = {
          ['ui-select'] = {
            require('telescope.themes').get_dropdown(),
          },
        },
      }

      -- Enable Telescope extensions if they are installed
      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')

      -- See `:help telescope.builtin`
      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
      vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>F', builtin.live_grep, { desc = '[S]earch by [G]rep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

      -- Slightly advanced example of overriding default behavior and theme
      vim.keymap.set('n', '<leader>/', function()
        -- You can pass additional configuration to Telescope to change the theme, layout, etc.
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 10,
          previewer = false,
        })
      end, { desc = '[/] Fuzzily search in current buffer' })

      -- It's also possible to pass additional configuration options.
      --  See `:help telescope.builtin.live_grep()` for information about particular keys
      vim.keymap.set('n', '<leader>s/', function()
        builtin.live_grep {
          grep_open_files = true,
          prompt_title = 'Live Grep in Open Files',
        }
      end, { desc = '[S]earch [/] in Open Files' })

      -- Shortcut for searching your Neovim configuration files
      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config' }
      end, { desc = '[S]earch [N]eovim files' })
    end,
  },

  { -- LSP Configuration & Plugins
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs and related tools to stdpath for Neovim
      { 'williamboman/mason.nvim', config = true }, -- NOTE: Must be loaded before dependants
      'williamboman/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- [[ rust-tools used in order to have clipy lints
      -- it uses rust_analyzer under the hod, it can be installed using 'rustup component add rust-analyser' ]]
      { 'simrat39/rust-tools.nvim' },
      -- Useful status updates for LSP.
      -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
      { 'j-hui/fidget.nvim', opts = {} },

      -- `neodev` configures Lua LSP for your Neovim config, runtime and plugins
      -- used for completion, annotations and signatures of Neovim apis
      { 'folke/neodev.nvim', opts = {} },
    },
    config = function()
      -- Brief aside: **What is LSP?**
      --
      -- LSP is an initialism you've probably heard, but might not understand what it is.
      --
      -- LSP stands for Language Server Protocol. It's a protocol that helps editors
      -- and language tooling communicate in a standardized fashion.
      --
      -- In general, you have a "server" which is some tool built to understand a particular
      -- language (such as `gopls`, `lua_ls`, `rust_analyzer`, etc.). These Language Servers
      -- (sometimes called LSP servers, but that's kind of like ATM Machine) are standalone
      -- processes that communicate with some "client" - in this case, Neovim!
      --
      -- LSP provides Neovim with features like:
      --  - Go to definition
      --  - Find references
      --  - Autocompletion
      --  - Symbol Search
      --  - and more!
      --
      -- Thus, Language Servers are external tools that must be installed separately from
      -- Neovim. This is where `mason` and related plugins come into play.
      --
      -- If you're wondering about lsp vs treesitter, you can check out the wonderfully
      -- and elegantly composed help section, `:help lsp-vs-treesitter`

      --  This function gets run when an LSP attaches to a particular buffer.
      --    That is to say, every time a new file is opened that is associated with
      --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
      --    function will be executed to configure the current buffer
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          -- NOTE: Remember that Lua is a real programming language, and as such it is possible
          -- to define small helper and utility functions so you don't have to repeat yourself.
          --
          -- In this case, we create a function that lets us more easily define mappings specific
          -- for LSP related items. It sets the mode, buffer and description for us each time.
          local map = function(keys, func, desc)
            vim.keymap.set('n', keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          -- Jump to the definition of the word under your cursor.
          --  This is where a variable was first declared, or where a function is defined, etc.
          --  To jump back, press <C-t>.
          map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')

          -- Find references for the word under your cursor.
          map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')

          -- Jump to the implementation of the word under your cursor.
          --  Useful when your language has ways of declaring types without an actual implementation.
          map('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')

          -- Jump to the type of the word under your cursor.
          --  Useful when you're not sure what type a variable is and you want to see
          --  the definition of its *type*, not where it was *defined*.
          map('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')

          -- Fuzzy find all the symbols in your current document.
          --  Symbols are things like variables, functions, types, etc.
          map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')

          -- Fuzzy find all the symbols in your current workspace.
          --  Similar to document symbols, except searches over your entire project.
          map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

          -- Rename the variable under your cursor.
          --  Most Language Servers support renaming across files, etc.
          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')

          -- Execute a code action, usually your cursor needs to be on top of an error
          -- or a suggestion from your LSP for this to activate.
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

          -- Opens a popup that displays documentation about the word under your cursor
          --  See `:help K` for why this keymap.
          -- map('K', vim.lsp.buf.hover, 'Hover Documentation')

          -- WARN: This is not Goto Definition, this is Goto Declaration.
          --  For example, in C this would take you to the header.
          map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          -- The following two autocommands are used to highlight references of the
          -- word under your cursor when your cursor rests there for a little while.
          --    See `:help CursorHold` for information about when this is executed
          --
          -- When you move your cursor, the highlights will be cleared (the second autocommand).
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.server_capabilities.documentHighlightProvider then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- The following autocommand is used to enable inlay hints in your
          -- code, if the language server you are using supports them
          --
          -- This may be unwanted, since they displace some of your code
          if client and client.server_capabilities.inlayHintProvider and vim.lsp.inlay_hint then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      -- LSP servers and clients are able to communicate to each other what features they support.
      --  By default, Neovim doesn't support everything that is in the LSP specification.
      --  When you add nvim-cmp, luasnip, etc. Neovim now has *more* capabilities.
      --  So, we create new capabilities with nvim cmp, and then broadcast that to the servers.
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())

      -- Enable the following language servers
      --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
      --
      --  Add any additional override configuration in the following tables. Available keys are:
      --  - cmd (table): Override the default command used to start the server
      --  - filetypes (table): Override the default list of associated filetypes for the server
      --  - capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
      --  - settings (table): Override the default settings passed when initializing the server.
      --        For example, to see the options for `lua_ls`, you could go to: https://luals.github.io/wiki/settings/
      local servers = {
        -- c/c++
        clangd = {},
        -- markdown
        marksman = {},
        -- python
        -- pylyzer = {},
        -- go
        gopls = {},
        pyright = {
          settings = {
            python = {
              analysis = {
                autoSearchPaths = true,
                useLibraryCodeFortypes = true,
              },
            },
          },
        },

        lua_ls = {
          -- cmd = {...},
          -- filetypes = { ...},
          -- capabilities = {},
          settings = {
            Lua = {
              completion = {
                callSnippet = 'Replace',
              },
              -- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
              diagnostics = { disable = { 'missing-fields' } },
            },
          },
        },
      }

      -- Ensure the servers and tools above are installed
      --  To check the current status of installed tools and/or manually install
      --  other tools, you can run
      --    :Mason
      --
      --  You can press `g?` for help in this menu.
      require('mason').setup()

      -- You can add other tools here that you want Mason to install
      -- for you, so that they are available from within Neovim.
      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, {
        'stylua', -- Used to format Lua code
      })
      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      require('mason-lspconfig').setup {
        handlers = {
          function(server_name)
            local server = servers[server_name] or {}
            -- This handles overriding only values explicitly passed
            -- by the server configuration above. Useful when disabling
            -- certain features of an LSP (for example, turning off formatting for tsserver)
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            require('lspconfig')[server_name].setup(server)
          end,
        },
      }

      require('rust-tools').setup {
        server = {
          settings = {

            ['rust-analyzer'] = {
              cargo = {
                allFeatures = true,
                loadOutDirsFromCheck = true,
                runBuildScripts = true,
              },
              -- Add clippy lints for Rust.
              checkOnSave = {
                allFeatures = true,
                command = 'clippy',
                extraArgs = {
                  '--',
                  '--no-deps',
                  '-Dclippy::correctness',
                  '-Dclippy::complexity',
                  '-Wclippy::perf',
                  -- '-Wclippy::pedantic',
                },
              },
              procMacro = {
                enable = true,
                ignored = {
                  ['async-trait'] = { 'async_trait' },
                  ['napi-derive'] = { 'napi' },
                  ['async-recursion'] = { 'async_recursion' },
                },
              },
            },
          },
        },
      }
    end,
  },

  { -- Autoformat
    'stevearc/conform.nvim',
    lazy = false,
    keys = {
      {
        '<leader>f',
        function()
          require('conform').format { async = true, lsp_fallback = true }
        end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        -- Disable "format_on_save lsp_fallback" for languages that don't
        -- have a well standardized coding style. You can add additional
        -- languages here or re-enable it for the disabled ones.
        local disable_filetypes = { c = true, cpp = true }
        return {
          timeout_ms = 500,
          lsp_fallback = not disable_filetypes[vim.bo[bufnr].filetype],
        }
      end,
      formatters_by_ft = {
        lua = { 'stylua' },
        -- Conform can also run multiple formatters sequentially
        -- python = { "isort", "black" },
        --
        -- You can use a sub-list to tell conform to run *until* a formatter
        -- is found.
        -- javascript = { { "prettierd", "prettier" } },
      },
    },
  },

  { -- Autocompletion
    'hrsh7th/nvim-cmp',
    event = 'InsertEnter',
    dependencies = {
      -- Snippet Engine & its associated nvim-cmp source
      {
        'L3MON4D3/LuaSnip',
        build = (function()
          -- Build Step is needed for regex support in snippets.
          -- This step is not supported in many windows environments.
          -- Remove the below condition to re-enable on windows.
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
            return
          end
          return 'make install_jsregexp'
        end)(),
        dependencies = {
          -- `friendly-snippets` contains a variety of premade snippets.
          --    See the README about individual language/framework/plugin snippets:
          --    https://github.com/rafamadriz/friendly-snippets
          -- {
          --   'rafamadriz/friendly-snippets',
          --   config = function()
          --     require('luasnip.loaders.from_vscode').lazy_load()
          --   end,
          -- },
        },
      },
      'saadparwaiz1/cmp_luasnip',

      -- Adds other completion capabilities.
      --  nvim-cmp does not ship with all sources by default. They are split
      --  into multiple repos for maintenance purposes.
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-path',
    },
    config = function()
      -- See `:help cmp`
      local cmp = require 'cmp'
      local luasnip = require 'luasnip'
      luasnip.config.setup {}

      cmp.setup {
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        completion = { completeopt = 'menu,menuone,noinsert' },

        -- For an understanding of why these mappings were
        -- chosen, you will need to read `:help ins-completion`
        --
        -- No, but seriously. Please read `:help ins-completion`, it is really good!
        mapping = cmp.mapping.preset.insert {
          -- Select the [n]ext item
          ['<C-n>'] = cmp.mapping.select_next_item(),
          -- Select the [p]revious item
          ['<C-p>'] = cmp.mapping.select_prev_item(),

          -- Scroll the documentation window [b]ack / [f]orward
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),

          -- Accept ([y]es) the completion.
          --  This will auto-import if your LSP supports it.
          --  This will expand snippets if the LSP sent a snippet.
          ['<C-y>'] = cmp.mapping.confirm { select = true },

          -- If you prefer more traditional completion keymaps,
          -- you can uncomment the following lines
          ['<CR>'] = cmp.mapping.confirm { select = true },
          --['<Tab>'] = cmp.mapping.select_next_item(),
          --['<S-Tab>'] = cmp.mapping.select_prev_item(),

          -- Manually trigger a completion from nvim-cmp.
          --  Generally you don't need this, because nvim-cmp will display
          --  completions whenever it has completion options available.
          ['<C-Space>'] = cmp.mapping.complete {},

          -- Think of <c-l> as moving to the right of your snippet expansion.
          --  So if you have a snippet that's like:
          --  function $name($args)
          --    $body
          --  end
          --
          -- <c-l> will move you to the right of each of the expansion locations.
          -- <c-h> is similar, except moving you backwards.
          ['<C-l>'] = cmp.mapping(function()
            if luasnip.expand_or_locally_jumpable() then
              luasnip.expand_or_jump()
            end
          end, { 'i', 's' }),
          ['<C-h>'] = cmp.mapping(function()
            if luasnip.locally_jumpable(-1) then
              luasnip.jump(-1)
            end
          end, { 'i', 's' }),

          -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
          --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
        },
        sources = {
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'path' },
        },
      }
    end,
  },

  { -- You can easily change to a different colorscheme.
    -- Change the name of the colorscheme plugin below, and then
    -- change the command in the config to whatever the name of that colorscheme is.
    --
    -- If you want to see what colorschemes are already installed, you can use `:Telescope colorscheme`.
    'folke/tokyonight.nvim',
    priority = 1000, -- Make sure to load this before all the other start plugins.
    init = function()
      -- Load the colorscheme here.
      -- Like many other themes, this one has different styles, and you could load
      -- any other, such as 'tokyonight-storm', 'tokyonight-moon', or 'tokyonight-day'.
      -- vim.cmd.colorscheme 'tokyonight-night'

      -- You can configure highlights by doing something like:
      vim.cmd.hi 'Comment gui=none'
    end,
  },

  -- Highlight todo, notes, etc in comments
  { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },

  { -- Collection of various small independent plugins/modules
    'echasnovski/mini.nvim',
    config = function()
      -- Better Around/Inside textobjects
      --
      -- Examples:
      --  - va)  - [V]isually select [A]round [)]paren
      --  - yinq - [Y]ank [I]nside [N]ext [']quote
      --  - ci'  - [C]hange [I]nside [']quote
      require('mini.ai').setup { n_lines = 500 }

      -- Add/delete/replace surroundings (brackets, quotes, etc.)
      --
      -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
      -- - sd'   - [S]urround [D]elete [']quotes
      -- - sr)'  - [S]urround [R]eplace [)] [']
      require('mini.surround').setup()

      -- Simple and easy statusline.
      --  You could remove this setup call if you don't like it,
      --  and try some other statusline plugin
      local statusline = require 'mini.statusline'

      -- Custom section for the location with percentage
      statusline.section_location = function()
        local line = vim.fn.line '.'
        local total_lines = vim.fn.line '$'
        local percentage = math.floor((line / total_lines) * 100)
        return string.format('%2d/%2d:%-2d %3d%%%%', line, total_lines, vim.fn.col '.', percentage)
      end

      statusline.setup {
        content = {
          -- Define the active section
          active = function()
            -- Sections for active statusline
            local mode, mode_hl = MiniStatusline.section_mode { trunc_width = 120 }
            local git = MiniStatusline.section_git { trunc_width = 75 }
            local diagnostics = MiniStatusline.section_diagnostics { trunc_width = 75 }
            local filename = MiniStatusline.section_filename { trunc_width = 140 }
            local fileinfo = MiniStatusline.section_fileinfo { trunc_width = 120 }
            local location = statusline.section_location()

            return MiniStatusline.combine_groups {
              { hl = mode_hl, strings = { mode } },
              { hl = 'MiniStatuslineDevinfo', strings = { git, diagnostics } },
              { hl = mode_hl, strings = { location } },
              '%<', -- Mark general truncate point
              { hl = 'MiniStatuslineFilename', strings = { filename } },
              '%=', -- End left alignment
              { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
            }
          end,

          -- Inactive statusline
          inactive = nil,
        },
        use_icons = vim.g.have_nerd_font,
      }

      ---@diagnostic disable-next-line: duplicate-set-field

      -- select the theme here
      vim.cmd.colorscheme 'minicyan'
      -- ... and there is more!
      --  Check out: https://github.com/echasnovski/mini.nvim
    end,
  },
  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    opts = {
      ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'vim', 'vimdoc', 'rust', 'python' },
      -- Autoinstall languages that are not installed
      auto_install = true,
      highlight = {
        enable = true,
        -- Some languages depend on vim's regex highlighting system (such as Ruby) for indent rules.
        --  If you are experiencing weird indenting issues, add the language to
        --  the list of additional_vim_regex_highlighting and disabled languages for indent.
        additional_vim_regex_highlighting = { 'ruby' },
      },
      indent = { enable = true, disable = { 'ruby' } },
      incremental_selection = {
        enable = true,
      },
      text_objects = {
        enable = true,
      },
      fold = {
        enable = true,
        disable = {},
      },
    },
    config = function(_, opts)
      -- [[ Configure Treesitter ]] See `:help nvim-treesitter`

      -- Prefer git instead of curl in order to improve connectivity in some environments
      require('nvim-treesitter.install').prefer_git = true
      ---@diagnostic disable-next-line: missing-fields
      require('nvim-treesitter.configs').setup(opts)

      vim.opt.foldmethod = 'expr'
      vim.opt.foldexpr = 'nvim_treesitter#foldexpr()'
      vim.opt.foldlevelstart = 99 -- open all folds by default

      -- fold custom levels
      vim.api.nvim_set_keymap('n', 'z1', ':set foldlevel=1<CR>', { noremap = true, silent = true })
      vim.api.nvim_set_keymap('n', 'z2', ':set foldlevel=2<CR>', { noremap = true, silent = true })
      vim.api.nvim_set_keymap('n', 'z3', ':set foldlevel=3<CR>', { noremap = true, silent = true })
      vim.api.nvim_set_keymap('n', 'z4', ':set foldlevel=4<CR>', { noremap = true, silent = true })
      vim.api.nvim_set_keymap('n', 'z5', ':set foldlevel=5<CR>', { noremap = true, silent = true })
      vim.api.nvim_set_keymap('n', 'z6', ':set foldlevel=6<CR>', { noremap = true, silent = true })
      -- There are additional nvim-treesitter modules that you can use to interact
      -- with nvim-treesitter. You should go explore a few and see what interests you:
      --
      --    - Incremental selection: Included, see `:help nvim-treesitter-incremental-selection-mod`
      --    - Show your current context: https://github.com/nvim-treesitter/nvim-treesitter-context
      --    - Treesitter + textobjects: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
    end,
  },

  -- The following two comments only work if you have downloaded the kickstart repo, not just copy pasted the
  -- init.lua. If you want these files, they are in the repository, so you can just download them and
  -- place them in the correct locations.

  -- NOTE: Next step on your Neovim journey: Add/Configure additional plugins for Kickstart
  --
  --  Here are some example plugins that I've included in the Kickstart repository.
  --  Uncomment any of the lines below to enable them (you will need to restart nvim).
  --
  -- require 'kickstart.plugins.debug',
  require 'kickstart.plugins.indent_line',
  -- require 'kickstart.plugins.lint',
  require 'kickstart.plugins.autopairs',
  -- require 'kickstart.plugins.neo-tree',
  require 'kickstart.plugins.gitsigns', -- adds gitsigns recommend keymaps

  -- NOTE: The import below can automatically add your own plugins, configuration, etc from `lua/custom/plugins/*.lua`
  --    This is the easiest way to modularize your config.
  --
  --  Uncomment the following line and add your plugins to `lua/custom/plugins/*.lua` to get going.
  --    For additional information, see `:help lazy.nvim-lazy.nvim-structuring-your-plugins`
  -- { import = 'custom.plugins' },
}, {
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
