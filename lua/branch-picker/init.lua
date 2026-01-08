-- Branch picker module with commit cherry-pick flow
local M = {}
local state = {
  buf = nil,
  win = nil,
  branches = {},
  selected_branches = {},
  selected_commits = {}, -- global across branches: { hash = true }
  callback = nil,
}

local function get_window_opts()
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.7)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  return { width = width, height = height, col = col, row = row }
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
  -- Put current branch first
  if current_branch then
    table.insert(branches, 1, current_branch)
  end
  return branches
end

local function get_commits(branch, limit)
  limit = limit or 200
  local cmd = 'git log --oneline -n ' .. limit .. ' ' .. branch .. ' 2>/dev/null'
  local handle = io.popen(cmd)
  if not handle then return {} end
  local result = handle:read('*a')
  handle:close()

  local commits = {}
  local i = 0
  for line in result:gmatch('[^\n]+') do
    local hash, subject = line:match('^(%S+)%s+(.*)$')
    if hash then
      table.insert(commits, { hash = hash, subject = subject, line = line, depth = i })
      i = i + 1
    end
  end
  return commits
end

local function render_branches()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local lines = {}
  for i, branch in ipairs(state.branches) do
    local prefix = state.selected_branches[branch.name] and '[x] ' or '[ ] '
    lines[i] = prefix .. branch.line
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function render_commits()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  -- Calculate max width for depth column (right-aligned)
  local max_depth = #state.commits - 1  -- 0-indexed, but 0 is hidden
  local depth_width = #tostring(max_depth) + 1  -- +1 for the minus sign

  local lines = {}
  for i, commit in ipairs(state.commits) do
    local depth_str
    if commit.depth == 0 then
      depth_str = string.rep(' ', depth_width + 1)  -- blank for HEAD
    else
      depth_str = string.format('%' .. depth_width .. 's ', '-' .. commit.depth)
    end
    local prefix = state.selected_commits[commit.hash] and '[x] ' or '[ ] '
    lines[i] = prefix .. depth_str .. commit.line
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function move_cursor(delta)
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local max_row = state.mode == 'branch' and #state.branches or #state.commits
  local new_row = math.max(1, math.min(max_row, pos[1] + delta))
  vim.api.nvim_win_set_cursor(state.win, { new_row, 0 })
end

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.branches = {}
  state.commits = {}
  state.selected_branches = {}
  state.selected_commits = {}
  state.mode = nil
end

local function update_title(title)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, { title = ' ' .. title .. ' ', title_pos = 'center' })
  end
end

local function setup_commit_keymaps()
  local opts = { buffer = state.buf, nowait = true, silent = true }

  -- Clear previous keymaps
  pcall(vim.keymap.del, 'n', 'j', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'k', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<Space>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<CR>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'd', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'q', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<Esc>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<BS>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'p', { buffer = state.buf })

  vim.keymap.set('n', 'j', function() move_cursor(1) end, opts)
  vim.keymap.set('n', 'k', function() move_cursor(-1) end, opts)

  vim.keymap.set('n', '<Space>', function()
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local commit = state.commits[pos[1]]
    if commit then
      if state.selected_commits[commit.hash] then
        state.selected_commits[commit.hash] = nil
      else
        state.selected_commits[commit.hash] = true
      end
      render_commits()
      move_cursor(1)
    end
  end, opts)

  vim.keymap.set('n', '<BS>', function()
    -- Go back to branch picker
    state.mode = 'branch'
    state.commits = {}
    render_branches()
    setup_branch_keymaps()
    update_title('Branches ([d]elete, [c]heckout, [n]ew, [r]ebase, [m]erge, [a]=fetch)')
  end, opts)

  vim.keymap.set('n', 'p', function()
    -- Check if any commits are selected
    local has_selected = false
    for _, _ in pairs(state.selected_commits) do
      has_selected = true
      break
    end
    if has_selected then
      vim.notify('Deselect commits first (space to toggle)', vim.log.levels.WARN)
      return
    end

    local status = vim.fn.system('git status --porcelain')
    if status ~= '' then
      vim.notify('Unstashed changes detected. Stash or commit before cherry-pick.', vim.log.levels.ERROR)
      return
    end

    local pos = vim.api.nvim_win_get_cursor(state.win)
    local commit = state.commits[pos[1]]
    if not commit then return end

    close()
    vim.cmd('Git cherry-pick ' .. commit.hash)
  end, opts)

  -- d: drop selected commits from this branch
  vim.keymap.set('n', 'd', function()
    local current = vim.fn.system('git branch --show-current'):gsub('%s+', '')
    if current ~= state.current_branch then
      vim.notify('Must be on branch ' .. state.current_branch .. ' to drop commits', vim.log.levels.ERROR)
      return
    end

    local status = vim.fn.system('git status --porcelain')
    if status ~= '' then
      vim.notify('Unstashed changes detected. Stash or commit before dropping.', vim.log.levels.ERROR)
      return
    end

    local hashes = {}
    for hash, _ in pairs(state.selected_commits) do
      table.insert(hashes, hash)
    end
    if #hashes == 0 then
      vim.notify('No commits selected', vim.log.levels.WARN)
      return
    end

    local prompt = #hashes == 1
      and ('Drop commit ' .. hashes[1] .. '? (y/N): ')
      or ('Drop ' .. #hashes .. ' commits? (y/N): ')

    vim.ui.input({ prompt = prompt }, function(input)
      if input and input:lower() == 'y' then
        -- Build sed script to drop selected commits
        local sed_parts = {}
        for _, hash in ipairs(hashes) do
          table.insert(sed_parts, 's/^pick ' .. hash .. '/drop ' .. hash .. '/')
        end
        local sed_script = table.concat(sed_parts, '; ')

        -- Find oldest commit to rebase from
        local oldest_hash = hashes[1]
        for _, commit in ipairs(state.commits) do
          for _, h in ipairs(hashes) do
            if commit.hash == h then
              oldest_hash = h
            end
          end
        end

        local cmd = string.format('GIT_SEQUENCE_EDITOR="sed -i \'%s\'" git rebase -i %s^', sed_script, oldest_hash)
        vim.fn.system(cmd)

        if vim.v.shell_error == 0 then
          vim.notify('Dropped ' .. #hashes .. ' commit(s)', vim.log.levels.INFO)
          state.selected_commits = {}
          state.commits = get_commits(state.current_branch)
          render_commits()
        else
          vim.notify('Failed to drop commits', vim.log.levels.ERROR)
        end
      end
    end)
  end, opts)

  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

local function open_commit_picker(branch)
  state.mode = 'commit'
  state.current_branch = branch
  state.commits = get_commits(branch)

  if #state.commits == 0 then
    vim.notify('No commits found in ' .. branch, vim.log.levels.WARN)
    return
  end

  render_commits()
  setup_commit_keymaps()
  update_title(branch .. ' ([d]rop, [p]ick, [backspace]=back)')
end

function setup_branch_keymaps()
  local opts = { buffer = state.buf, nowait = true, silent = true }

  -- Clear previous keymaps
  pcall(vim.keymap.del, 'n', 'j', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'k', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<Space>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<CR>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'd', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'q', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<Esc>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', '<BS>', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'p', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'c', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'n', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'a', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'r', { buffer = state.buf })
  pcall(vim.keymap.del, 'n', 'm', { buffer = state.buf })

  vim.keymap.set('n', 'j', function() move_cursor(1) end, opts)
  vim.keymap.set('n', 'k', function() move_cursor(-1) end, opts)

  -- Space: toggle select and move down
  vim.keymap.set('n', '<Space>', function()
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local branch = state.branches[pos[1]]
    if branch then
      if state.selected_branches[branch.name] then
        state.selected_branches[branch.name] = nil
      else
        state.selected_branches[branch.name] = true
      end
      render_branches()
      move_cursor(1)
    end
  end, opts)

  -- d: delete branch(es) with confirmation
  vim.keymap.set('n', 'd', function()
    local to_delete = {}
    -- Get selected branches, or focused if none selected
    for name, _ in pairs(state.selected_branches) do
      table.insert(to_delete, name)
    end
    if #to_delete == 0 then
      local pos = vim.api.nvim_win_get_cursor(state.win)
      local branch = state.branches[pos[1]]
      if branch then
        to_delete = { branch.name }
      end
    end

    -- Filter out current branch
    local filtered = {}
    for _, name in ipairs(to_delete) do
      local is_current = false
      for _, b in ipairs(state.branches) do
        if b.name == name and b.current then
          is_current = true
          break
        end
      end
      if is_current then
        vim.notify('Cannot delete current branch: ' .. name, vim.log.levels.ERROR)
      else
        table.insert(filtered, name)
      end
    end

    if #filtered == 0 then return end

    local prompt = #filtered == 1
      and ('Delete branch ' .. filtered[1] .. '? (y/N): ')
      or ('Delete ' .. #filtered .. ' branches? (y/N): ')

    vim.ui.input({ prompt = prompt }, function(input)
      if input and input:lower() == 'y' then
        for _, name in ipairs(filtered) do
          vim.fn.system('git branch -D ' .. name)
        end
        vim.notify('Deleted ' .. #filtered .. ' branch(es)', vim.log.levels.INFO)
        state.selected_branches = {}
        state.branches = get_branches()
        render_branches()
      end
    end)
  end, opts)

  -- c: checkout branch
  vim.keymap.set('n', 'c', function()
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local branch = state.branches[pos[1]]
    if branch then
      vim.cmd('Git checkout ' .. branch.name)
      state.branches = get_branches()
      render_branches()
    end
  end, opts)

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
        state.branches = get_branches()
        render_branches()
        vim.notify('Fetch complete', vim.log.levels.INFO)
      end
    })
  end, opts)

  -- n: new branch
  vim.keymap.set('n', 'n', function()
    vim.ui.input({ prompt = 'New branch name: ' }, function(name)
      if not name or name == '' then return end
      -- Check if branch exists
      for _, b in ipairs(state.branches) do
        if b.name == name then
          vim.notify('Branch ' .. name .. ' already exists', vim.log.levels.ERROR)
          return
        end
      end
      vim.cmd('Git checkout -b ' .. name)
      state.branches = get_branches()
      render_branches()
    end)
  end, opts)

  -- r: rebase onto focused branch
  vim.keymap.set('n', 'r', function()
    local status = vim.fn.system('git status --porcelain')
    if status ~= '' then
      vim.notify('Unstashed changes detected. Stash or commit before rebase.', vim.log.levels.ERROR)
      return
    end

    local pos = vim.api.nvim_win_get_cursor(state.win)
    local branch = state.branches[pos[1]]
    if not branch then return end

    if branch.current then
      vim.notify('Cannot rebase onto self', vim.log.levels.ERROR)
      return
    end

    close()
    vim.cmd('Git rebase ' .. branch.name)
  end, opts)

  -- m: merge focused branch
  vim.keymap.set('n', 'm', function()
    local status = vim.fn.system('git status --porcelain')
    if status ~= '' then
      vim.notify('Unstashed changes detected. Stash or commit before merge.', vim.log.levels.ERROR)
      return
    end

    local pos = vim.api.nvim_win_get_cursor(state.win)
    local branch = state.branches[pos[1]]
    if not branch then return end

    if branch.current then
      vim.notify('Cannot merge self', vim.log.levels.ERROR)
      return
    end

    close()
    vim.cmd('Git merge ' .. branch.name)
  end, opts)

  -- Enter: open commit picker for focused branch
  vim.keymap.set('n', '<CR>', function()
    local pos = vim.api.nvim_win_get_cursor(state.win)
    local branch = state.branches[pos[1]]
    if branch then
      open_commit_picker(branch.name)
    end
  end, opts)

  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

function M.open(opts)
  opts = opts or {}

  state.branches = get_branches()
  if #state.branches == 0 then
    vim.notify('No branches found', vim.log.levels.WARN)
    return
  end

  state.selected_branches = {}
  state.selected_commits = {}
  state.mode = 'branch'

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
    title = ' Branches ([d]elete, [c]heckout, [n]ew, [r]ebase, [m]erge, [a]=fetch) ',
    title_pos = 'center',
  })

  vim.wo[state.win].cursorline = true
  vim.wo[state.win].wrap = false
  vim.wo[state.win].winhighlight = 'NormalFloat:Normal'

  render_branches()
  setup_branch_keymaps()
end

function M.setup()
  -- No default keymaps, used programmatically via M.open()
end

return M
