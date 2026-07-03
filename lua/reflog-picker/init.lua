-- Reflog picker module for selecting a git reflog entry
local M = {}
local state = { buf = nil, win = nil, entries = {}, callback = nil, on_back = nil, title = nil }

local function get_window_opts()
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.7)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  return { width = width, height = height, col = col, row = row }
end

local function get_reflog(limit)
  local handle = io.popen('git reflog -n ' .. limit .. ' 2>/dev/null')
  if not handle then return {} end
  local result = handle:read('*a')
  handle:close()

  local entries = {}
  for line in result:gmatch('[^\n]+') do
    local hash, n, message = line:match('^(%S+)%s+HEAD@{(%d+)}:%s*(.*)$')
    if hash then
      -- HEAD@{0} is one commit back from the picker's point of view, so display -1
      local display = string.format('-%d %s: %s', tonumber(n) + 1, hash, message)
      table.insert(entries, { hash = hash, line = display })
    end
  end
  return entries
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local lines = {}
  for i, entry in ipairs(state.entries) do
    lines[i] = entry.line
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function move_cursor(delta)
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local new_row = math.max(1, math.min(#state.entries, pos[1] + delta))
  vim.api.nvim_win_set_cursor(state.win, { new_row, 0 })
end

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.entries = {}
  state.callback = nil
  state.on_back = nil
  state.title = nil
end

local function confirm()
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local entry = state.entries[pos[1]]
  if not entry then return end

  local hash = entry.hash
  local callback = state.callback
  close()

  if callback then
    callback(hash)
  end
end

local function setup_keymaps()
  local opts = { buffer = state.buf, nowait = true, silent = true }

  vim.keymap.set('n', 'j', function() move_cursor(1) end, opts)
  vim.keymap.set('n', 'k', function() move_cursor(-1) end, opts)
  vim.keymap.set('n', '<CR>', confirm, opts)
  if state.on_back then
    vim.keymap.set('n', '<BS>', function()
      local cb = state.on_back
      close()
      cb()
    end, opts)
  end
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

function M.open(opts)
  opts = opts or {}
  local limit = opts.limit or 200

  state.entries = get_reflog(limit)
  if #state.entries == 0 then
    vim.notify('No reflog entries found', vim.log.levels.WARN)
    return
  end

  state.callback = opts.callback
  state.on_back = opts.on_back
  state.title = opts.title

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
    title = ' ' .. (state.title or 'Reflog Picker')
      .. ' (enter=confirm'
      .. (state.on_back and ', backspace=back' or '')
      .. ', q=close) ',
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
