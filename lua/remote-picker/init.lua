-- Remote picker module with push/pull flow
local M = {}
local state = {
  buf = nil,
  win = nil,
  remotes = {},
  branches = {},
  mode = 'remote',  -- 'remote' or 'branch'
  selected_remote = nil,
}

local function get_window_opts()
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.7)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  return { width = width, height = height, col = col, row = row }
end

local function get_remotes()
  local handle = io.popen('git remote 2>/dev/null')
  if not handle then return {} end
  local result = handle:read('*a')
  handle:close()

  local all_remotes = {}
  for line in result:gmatch('[^\n]+') do
    local name = line:gsub('%s+', '')
    if name and name ~= '' then
      table.insert(all_remotes, { name = name })
    end
  end

  local last_remote = vim.g.last_remote_action and vim.g.last_remote_action.remote or nil

  -- Sort: last-used first, origin last, others alphabetically
  table.sort(all_remotes, function(a, b)
    -- Last-used remote always first
    if a.name == last_remote then return true end
    if b.name == last_remote then return false end
    -- Origin always last
    if a.name == 'origin' then return false end
    if b.name == 'origin' then return true end
    -- Others alphabetically
    return a.name < b.name
  end)

  return all_remotes
end

local function get_branches()
  local handle = io.popen('git branch 2>/dev/null')
  if not handle then return {} end
  local result = handle:read('*a')
  handle:close()

  local branches = {}
  local current_branch = nil
  for line in result:gmatch('[^\n]+') do
    local current = line:match('^%*') ~= nil
    local name = line:gsub('^%*?%s*', '')
    if name and name ~= '' then
      local branch = { name = name, current = current, line = current and ('*' .. name) or name }
      if current then
        current_branch = branch
      else
        table.insert(branches, branch)
      end
    end
  end

  -- Sort alphabetically
  table.sort(branches, function(a, b) return a.name < b.name end)

  -- Put current branch first
  if current_branch then
    table.insert(branches, 1, current_branch)
  end

  return branches
end

local function render_remotes()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local lines = {}
  for i, remote in ipairs(state.remotes) do
    lines[i] = remote.name
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function render_branches()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local lines = {}
  for i, branch in ipairs(state.branches) do
    lines[i] = branch.line
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function move_cursor(delta)
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local max_row = state.mode == 'remote' and #state.remotes or #state.branches
  local new_row = math.max(1, math.min(max_row, pos[1] + delta))
  vim.api.nvim_win_set_cursor(state.win, { new_row, 0 })
end

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.remotes = {}
  state.branches = {}
  state.mode = nil
  state.selected_remote = nil
end

local function update_title(title)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, { title = ' ' .. title .. ' ', title_pos = 'center' })
  end
end

local function setup_branch_keymaps()
  local opts = { buffer = state.buf, nowait = true, silent = true }

  -- Clear previous keymaps
  pcall(vim.keymap.del, 'n', 'j', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'k', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<CR>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'a', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'q', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<Esc>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<BS>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 's', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'fs', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'l', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'fl', { buffer = state.buf })

  vim.keymap.set('n', 'j', function() move_cursor(1) end, opts)
  vim.keymap.set('n', 'k', function() move_cursor(-1) end, opts)

  -- s: push
  vim.keymap.set('n', 's', function()
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local branch = state.branches[pos[1]]
    if not branch then return end

    local remote = state.selected_remote
    vim.g.last_remote_action = { remote = remote }
    close()
    vim.cmd('Git push ' .. remote .. ' ' .. branch.name)
  end, opts)

  -- fs: push --force
  vim.keymap.set('n', 'fs', function()
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local branch = state.branches[pos[1]]
    if not branch then return end

    local remote = state.selected_remote
    vim.g.last_remote_action = { remote = remote }
    close()
    vim.cmd('Git push --force ' .. remote .. ' ' .. branch.name)
  end, opts)

  -- l: pull
  vim.keymap.set('n', 'l', function()
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local branch = state.branches[pos[1]]
    if not branch then return end

    local remote = state.selected_remote
    vim.g.last_remote_action = { remote = remote }
    close()
    vim.cmd('Git pull ' .. remote .. ' ' .. branch.name)
  end, opts)

  -- fl: pull --force
  vim.keymap.set('n', 'fl', function()
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local branch = state.branches[pos[1]]
    if not branch then return end

    local remote = state.selected_remote
    vim.g.last_remote_action = { remote = remote }
    close()
    vim.cmd('Git pull --force ' .. remote .. ' ' .. branch.name)
  end, opts)

  -- Backspace: go back to remote picker
  vim.keymap.set('n', '<BS>', function()
    state.mode = 'remote'
    state.branches = {}
    state.selected_remote = nil
    render_remotes()
    setup_remote_keymaps()
    update_title('Remotes ([a]=fetch all)')
  end, opts)

  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

local function open_branch_picker(remote)
  state.mode = 'branch'
  state.selected_remote = remote
  state.branches = get_branches()

  if #state.branches == 0 then
    vim.notify('No branches found', vim.log.levels.WARN)
    return
  end

  render_branches()
  setup_branch_keymaps()
  update_title(remote .. ' (pu[s]h, [f]orce pu[s]h, pu[l]l, [f]orce pu[l]l, [backspace]=back)')
end

function setup_remote_keymaps()
  local opts = { buffer = state.buf, nowait = true, silent = true }

  -- Clear previous keymaps
  pcall(vim.keymap.del, 'n', 'j', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'k', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<CR>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'a', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'q', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<Esc>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<BS>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 's', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'fs', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'l', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'fl', { buffer = state.buf })

  vim.keymap.set('n', 'j', function() move_cursor(1) end, opts)
  vim.keymap.set('n', 'k', function() move_cursor(-1) end, opts)

  -- a: fetch all
  vim.keymap.set('n', 'a', function()
    local spinner = { '|', '/', '-', '\\' }
    local spin_idx = 1
    local timer = vim.loop.new_timer()

    local function update_footer(text)
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_set_config(state.win, { footer = ' ' .. text .. ' ', footer_pos = 'center' })
      end
    end

    local function update_spinner()
      if not state.win or not vim.api.nvim_win_is_valid(state.win) then
        timer:stop()
        return
      end
      update_footer('Fetching... ' .. spinner[spin_idx])
      spin_idx = (spin_idx % #spinner) + 1
    end

    update_spinner()
    timer:start(0, 100, vim.schedule_wrap(update_spinner))

    vim.fn.jobstart('git fetch --all', {
      on_exit = function()
        timer:stop()
        if state.win and vim.api.nvim_win_is_valid(state.win) then
          vim.api.nvim_win_set_config(state.win, { footer = '', footer_pos = 'center' })
        end
        state.remotes = get_remotes()
        render_remotes()
        vim.notify('Fetch complete', vim.log.levels.INFO)
      end
    })
  end, opts)

  -- Enter: open branch picker for focused remote
  vim.keymap.set('n', '<CR>', function()
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local remote = state.remotes[pos[1]]
    if remote then
      open_branch_picker(remote.name)
    end
  end, opts)

  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

function M.open(opts)
  opts = opts or {}

  state.remotes = get_remotes()
  if #state.remotes == 0 then
    vim.notify('No remotes found', vim.log.levels.WARN)
    return
  end

  state.branches = {}
  state.mode = 'remote'
  state.selected_remote = nil

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
    title = ' Remotes ([a]=fetch all) ',
    title_pos = 'center',
  })

  vim.wo[state.win].cursorline = true
  vim.wo[state.win].wrap = false
  vim.wo[state.win].winhighlight = 'NormalFloat:Normal'

  render_remotes()
  setup_remote_keymaps()
end

function M.setup()
  -- No default keymaps, used programmatically via M.open()
end

return M
