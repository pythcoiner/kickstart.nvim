-- Commit checkpoints: persist the last few commits per repo and pick one to diff against
local M = {}
local MAX = 10
local state = { buf = nil, win = nil, entries = {}, callback = nil }

-- Path to this repo's checkpoint file, inside the git dir so it is never committed
local function store_path()
  local dir = vim.fn.system('git rev-parse --absolute-git-dir 2>/dev/null'):gsub('%s+', '')
  if vim.v.shell_error ~= 0 or dir == '' then
    return nil
  end
  return dir .. '/checkpoints.json'
end

local function read_list(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local ok, list = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
  end)
  if not ok or type(list) ~= 'table' then
    return {}
  end
  return list
end

local function write_list(path, list)
  local file = io.open(path, 'w')
  if not file then
    vim.notify('Cannot write ' .. path, vim.log.levels.ERROR)
    return
  end
  file:write(vim.json.encode(list))
  file:close()
end

function M.record()
  local path = store_path()
  if not path then
    vim.notify('Not a git repo, cannot record checkpoint', vim.log.levels.ERROR)
    return
  end

  local hash = vim.fn.system('git rev-parse --short HEAD'):gsub('%s+', '')
  if vim.v.shell_error ~= 0 or hash == '' then
    vim.notify('No commit to record', vim.log.levels.ERROR)
    return
  end
  local subject = vim.fn.system('git log -1 --format=%s ' .. hash):gsub('%s+$', '')

  local list = read_list(path)
  -- Dedupe: drop an existing entry for this commit so it moves back to the top
  for i = #list, 1, -1 do
    if list[i].hash == hash then
      table.remove(list, i)
    end
  end
  table.insert(list, 1, { hash = hash, subject = subject, time = os.date('%Y-%m-%d %H:%M:%S') })
  while #list > MAX do
    table.remove(list)
  end
  write_list(path, list)
  vim.notify('Checkpoint ' .. hash .. ' recorded', vim.log.levels.INFO)
end

local function get_window_opts()
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.7)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  return { width = width, height = height, col = col, row = row }
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local lines = {}
  for i, entry in ipairs(state.entries) do
    if entry.branch then
      lines[i] = entry.branch
    else
      local label = (entry.comment and entry.comment ~= '') and entry.comment or entry.subject
      lines[i] = string.format('%s  %s  (%s)', entry.hash, label, entry.time)
    end
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
  state.path = nil
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

local function checkout()
  local status = vim.fn.system('git status --porcelain')
  if status ~= '' then
    vim.notify('Unstashed changes detected. Stash or commit before checkout.', vim.log.levels.ERROR)
    return
  end

  local pos = vim.api.nvim_win_get_cursor(state.win)
  local entry = state.entries[pos[1]]
  if not entry then return end

  close()
  vim.cmd('Git checkout ' .. (entry.branch or entry.hash))
end

-- Persist only real checkpoints; synthetic entries (e.g. the master branch) are not saved
local function persist()
  local real = {}
  for _, e in ipairs(state.entries) do
    if not e.branch then real[#real + 1] = e end
  end
  write_list(state.path, real)
end

local function remove()
  local pos = vim.api.nvim_win_get_cursor(state.win)[1]
  local entry = state.entries[pos]
  if not entry then return end
  if entry.branch then
    vim.notify('Cannot delete a branch entry', vim.log.levels.WARN)
    return
  end
  table.remove(state.entries, pos)
  persist()
  if #state.entries == 0 then
    close()
    vim.notify('No checkpoints left', vim.log.levels.INFO)
    return
  end
  render()
  vim.api.nvim_win_set_cursor(state.win, { math.min(pos, #state.entries), 0 })
end

-- Set/edit a comment shown instead of the commit message; empty input clears it
local function comment()
  local entry = state.entries[vim.api.nvim_win_get_cursor(state.win)[1]]
  if not entry then return end
  if entry.branch then
    vim.notify('Cannot comment a branch entry', vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = 'Comment (empty to clear): ', default = entry.comment or '' }, function(input)
    if input == nil then return end
    entry.comment = input ~= '' and input or nil
    persist()
    render()
  end)
end

local function setup_keymaps()
  local opts = { buffer = state.buf, nowait = true, silent = true }

  vim.keymap.set('n', 'j', function() move_cursor(1) end, opts)
  vim.keymap.set('n', 'k', function() move_cursor(-1) end, opts)
  vim.keymap.set('n', '<CR>', confirm, opts)
  vim.keymap.set('n', 'c', checkout, opts)
  vim.keymap.set('n', 'a', comment, opts)
  vim.keymap.set('n', 'd', remove, opts)
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

function M.pick(callback)
  local path = store_path()
  if not path then
    vim.notify('Not a git repo', vim.log.levels.ERROR)
    return
  end

  state.entries = read_list(path)

  -- Offer the master branch as a selectable base too, when it exists and isn't already a checkpoint
  local mhash = vim.fn.system('git rev-parse --verify --quiet --short master'):gsub('%s+', '')
  if vim.v.shell_error == 0 and mhash ~= '' then
    local dup = false
    for _, e in ipairs(state.entries) do
      if e.hash == mhash then dup = true break end
    end
    if not dup then
      table.insert(state.entries, { hash = mhash, branch = 'master' })
    end
  end

  if #state.entries == 0 then
    vim.notify('No checkpoints (use <leader>cp)', vim.log.levels.WARN)
    return
  end

  state.callback = callback
  state.path = path

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = 'nofile'
  vim.bo[state.buf].bufhidden = 'wipe'

  local win_opts = get_window_opts()
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = 'editor',
    width = win_opts.width,
    height = win_opts.height,
    col = win_opts.col,
    row = win_opts.row,
    style = 'minimal',
    border = 'rounded',
    title = ' Checkpoints (enter=diff, [c]heckout, [a]comment, [d]elete, q=close) ',
    title_pos = 'center',
  })

  vim.wo[state.win].cursorline = true
  vim.wo[state.win].wrap = false
  vim.wo[state.win].winhighlight = 'NormalFloat:Normal'

  render()
  setup_keymaps()
end

function M.setup()
  -- No default keymaps, used programmatically via M.record()/M.pick()
end

return M
