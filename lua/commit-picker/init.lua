-- Commit picker module for selecting git commits
local M = {}
local state = { buf = nil, win = nil, commits = {}, selected = {}, callback = nil }

local function get_window_opts()
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.7)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  return { width = width, height = height, col = col, row = row }
end

local function get_commits(limit)
  local handle = io.popen('git log --oneline -n ' .. limit .. ' 2>/dev/null')
  if not handle then return {} end
  local result = handle:read('*a')
  handle:close()

  local commits = {}
  for line in result:gmatch('[^\n]+') do
    local hash, subject = line:match('^(%S+)%s+(.*)$')
    if hash then
      table.insert(commits, { hash = hash, subject = subject, line = line })
    end
  end
  return commits
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local lines = {}
  for i, commit in ipairs(state.commits) do
    local prefix = state.selected[commit.hash] and '[x] ' or '[ ] '
    lines[i] = prefix .. commit.line
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- Highlight selected lines
  vim.api.nvim_buf_clear_namespace(state.buf, -1, 0, -1)
  for i, commit in ipairs(state.commits) do
    if state.selected[commit.hash] then
      vim.api.nvim_buf_add_highlight(state.buf, -1, 'Visual', i - 1, 0, -1)
    end
  end
end

local function move_cursor(delta)
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local new_row = math.max(1, math.min(#state.commits, pos[1] + delta))
  vim.api.nvim_win_set_cursor(state.win, { new_row, 0 })
end

local function toggle_selection()
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local commit = state.commits[pos[1]]
  if commit then
    if state.selected[commit.hash] then
      state.selected[commit.hash] = nil
    else
      state.selected[commit.hash] = true
    end
    render()
    -- Move to next line
    move_cursor(1)
  end
end

local function get_selected_hashes()
  local hashes = {}
  -- Preserve order based on commits list
  for _, commit in ipairs(state.commits) do
    if state.selected[commit.hash] then
      table.insert(hashes, commit.hash)
    end
  end
  return hashes
end

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.commits = {}
  state.selected = {}
  state.callback = nil
end

local function confirm()
  local hashes = get_selected_hashes()

  -- If nothing selected, use current line
  if #hashes == 0 then
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local commit = state.commits[pos[1]]
    if commit then
      hashes = { commit.hash }
    end
  end

  local callback = state.callback
  close()

  -- Debug log
  vim.notify('[' .. table.concat(hashes, ', ') .. '] selected', vim.log.levels.INFO)

  if callback then
    callback(hashes)
  end
end

local function setup_keymaps()
  local opts = { buffer = state.buf, nowait = true, silent = true }

  vim.keymap.set('n', 'j', function() move_cursor(1) end, opts)
  vim.keymap.set('n', 'k', function() move_cursor(-1) end, opts)
  vim.keymap.set('n', '<Space>', toggle_selection, opts)
  vim.keymap.set('n', '<CR>', confirm, opts)
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

function M.open(opts)
  opts = opts or {}
  local limit = opts.limit or 50

  state.commits = get_commits(limit)
  if #state.commits == 0 then
    vim.notify('No commits found', vim.log.levels.WARN)
    return
  end

  state.selected = {}
  state.callback = opts.callback

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = 'nofile'
  vim.bo[state.buf].bufhidden = 'wipe'

  -- Open floating window
  local win_opts = get_window_opts()
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = 'editor',
    width = win_opts.width,
    height = win_opts.height,
    col = win_opts.col,
    row = win_opts.row,
    style = 'minimal',
    border = 'rounded',
    title = ' Commit Picker (space=select, enter=confirm, q=close) ',
    title_pos = 'center',
  })

  vim.wo[state.win].cursorline = true
  vim.wo[state.win].wrap = false

  render()
  setup_keymaps()
end

function M.setup()
  vim.keymap.set('n', '<leader>cp', function() M.open() end, { desc = 'Commit picker' })
end

return M
