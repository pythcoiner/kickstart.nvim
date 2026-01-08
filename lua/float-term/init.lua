-- Simple floating terminal module
local M = {}
local state = { buf = nil, win = nil, position = nil }

local function get_opts(position)
  local height = math.floor(vim.o.lines * 0.8) - 2
  local row = math.floor((vim.o.lines - height) / 2) - 2

  if position == 'center' then
    local width = math.floor(vim.o.columns * 0.8) - 15
    return { width = width, height = height, col = math.floor((vim.o.columns - width) / 2) + 15, row = row }
  else -- right
    local width = math.floor(vim.o.columns * 0.5)
    return { width = width, height = height, col = vim.o.columns - width, row = row }
  end
end

local function open(position)
  local opts = get_opts(position)

  -- Create buffer if needed
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
  end

  -- Open floating window
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = 'editor',
    width = opts.width,
    height = opts.height,
    col = opts.col,
    row = opts.row,
    style = 'minimal',
    border = 'rounded',
  })
  vim.wo[state.win].winblend = position == 'right' and 30 or 0
  state.position = position

  -- Start terminal if buffer is empty
  if vim.bo[state.buf].buftype ~= 'terminal' then
    vim.cmd.terminal()
  end
  vim.cmd.startinsert()
end

local function toggle(position)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    if state.position == position then
      vim.api.nvim_win_hide(state.win)
      state.win = nil
    else
      -- Move to new position
      vim.api.nvim_win_hide(state.win)
      state.win = nil
      open(position)
    end
  else
    open(position)
  end
end

function M.toggle_center() toggle('center') end
function M.toggle_right() toggle('right') end

function M.setup()
  vim.keymap.set('n', '<leader>ct', M.toggle_center, { desc = 'Toggle floating terminal (center)' })
  vim.keymap.set('n', '<leader>cy', M.toggle_right, { desc = 'Toggle floating terminal (right)' })
end

return M
