-- File picker module for selecting edited files
local M = {}
local state = { buf = nil, win = nil, files = {}, selected = {}, callback = nil }

local function get_window_opts()
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.7)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  return { width = width, height = height, col = col, row = row }
end

local function get_files()
  local handle = io.popen('git status --porcelain 2>/dev/null')
  if not handle then return {} end
  local result = handle:read('*a')
  handle:close()

  local files = {}
  for line in result:gmatch('[^\n]+') do
    local status, path = line:match('^(..)%s+(.+)$')
    if status and path then
      table.insert(files, { status = status, path = path, line = line })
    end
  end
  return files
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local lines = {}
  for i, file in ipairs(state.files) do
    if state.multiselect then
      local prefix = state.selected[file.path] and '[x] ' or '[ ] '
      lines[i] = prefix .. file.line
    else
      lines[i] = file.line
    end
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function move_cursor(delta)
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local new_row = math.max(1, math.min(#state.files, pos[1] + delta))
  vim.api.nvim_win_set_cursor(state.win, { new_row, 0 })
end

local function toggle_selection()
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local file = state.files[pos[1]]
  if file then
    if state.selected[file.path] then
      state.selected[file.path] = nil
    else
      state.selected[file.path] = true
    end
    render()
    move_cursor(1)
  end
end

local function get_selected_paths()
  local paths = {}
  for _, file in ipairs(state.files) do
    if state.selected[file.path] then
      table.insert(paths, file.path)
    end
  end
  return paths
end

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.files = {}
  state.selected = {}
  state.callback = nil
end

local function confirm()
  local paths = get_selected_paths()

  -- If nothing selected, use current line
  if #paths == 0 then
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local file = state.files[pos[1]]
    if file then
      paths = { file.path }
    end
  end

  local callback = state.callback
  close()

  vim.notify('[' .. table.concat(paths, ', ') .. '] selected', vim.log.levels.INFO)

  if callback then
    callback(paths)
  end
end

local function setup_keymaps()
  local opts = { buffer = state.buf, nowait = true, silent = true }

  vim.keymap.set('n', 'j', function() move_cursor(1) end, opts)
  vim.keymap.set('n', 'k', function() move_cursor(-1) end, opts)
  if state.multiselect then
    vim.keymap.set('n', '<Space>', toggle_selection, opts)
  end
  vim.keymap.set('n', '<CR>', confirm, opts)
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

function M.open(opts)
  opts = opts or {}

  state.files = get_files()
  if #state.files == 0 then
    vim.notify('No changed files', vim.log.levels.WARN)
    return
  end

  state.selected = {}
  state.callback = opts.callback
  state.title = opts.title
  state.multiselect = opts.multiselect ~= false -- default true

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
    title = ' ' .. (state.title or 'File Picker') .. (state.multiselect and ' (space=select, enter=confirm, q=close) ' or ' (enter=confirm, q=close) '),
    title_pos = 'center',
  })

  vim.wo[state.win].cursorline = true
  vim.wo[state.win].wrap = false
  vim.wo[state.win].winhighlight = 'NormalFloat:Normal'

  render()
  setup_keymaps()
end

function M.setup()
  -- No default keymaps, used programmatically via M.open()
end

return M
