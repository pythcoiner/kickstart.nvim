-- Tree-diff session: compare the picked checkpoint against the commit checked out
-- when the session starts, browse the range-diff series, and check out / diff any entry.
-- Session state persists in the git dir so it survives restart and is torn down explicitly.
local M = {}
local state = {}

local function git(cmd)
  local out = vim.fn.system('git ' .. cmd)
  return out:gsub('%s+$', ''), vim.v.shell_error
end

-- Session file lives in the git dir, so it is never committed and is naturally per-repo
local function store_path()
  local dir = vim.fn.system('git rev-parse --absolute-git-dir 2>/dev/null'):gsub('%s+', '')
  if vim.v.shell_error ~= 0 or dir == '' then
    return nil
  end
  return dir .. '/hv-session.json'
end

local function session_exists()
  local p = store_path()
  return p ~= nil and vim.fn.filereadable(p) == 1
end

local function load()
  local p = store_path()
  if not p or vim.fn.filereadable(p) == 0 then return nil end
  local ok, s = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(p), '\n'))
  end)
  if not ok or type(s) ~= 'table' then return nil end
  return s
end

local function save(s)
  local p = store_path()
  if not p then return end
  local f = io.open(p, 'w')
  if not f then
    vim.notify('Cannot write ' .. p, vim.log.levels.ERROR)
    return
  end
  f:write(vim.json.encode(s))
  f:close()
end

local function clear()
  local p = store_path()
  if p then os.remove(p) end
end

local function endpoints_alive(s)
  if not s or not s.A or not s.B then return false end
  local function alive(sha)
    local _, err = git('cat-file -e ' .. sha .. '^{commit}')
    return err == 0
  end
  return alive(s.A.sha) and alive(s.B.sha)
end

local function get_window_opts()
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.7)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  return { width = width, height = height, col = col, row = row }
end

local PREFIX = { ['>'] = '+', ['<'] = '-', ['!'] = '~' }

-- Build display rows top-to-bottom: newest diff entry first, consecutive unchanged
-- commits collapsed into one [...] line, merge-base as a non-selectable bottom row.
local function build_rows(session)
  local rows = {}
  local run = 0
  local function flush()
    if run > 0 then
      rows[#rows + 1] = { selectable = false, line = string.format('[...] (%d unchanged)', run) }
      run = 0
    end
  end
  for i = #session.entries, 1, -1 do
    local e = session.entries[i]
    if e.status == '=' then
      run = run + 1
    else
      flush()
      rows[#rows + 1] = { selectable = true, entry = e, prefix = PREFIX[e.status] }
    end
  end
  flush()
  local mb = session.merge_base ~= '' and session.merge_base:sub(1, 7) or '(none)'
  rows[#rows + 1] = { selectable = false, line = string.format('  %s  %s  (merge-base)', mb, session.merge_base_subject) }
  return rows
end

local function row_line(row)
  if not row.selectable then return row.line end
  local e = row.entry
  local marks = e.empty_tree and ' (root)' or ''
  return string.format('%s %s  %s%s', row.prefix, e.checkout_target, e.subject, marks)
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local lines = {}
  for i, row in ipairs(state.rows) do
    lines[i] = row_line(row)
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

-- Move to the next selectable row in the delta direction, skipping [...] / merge-base
local function move_cursor(delta)
  local pos = vim.api.nvim_win_get_cursor(state.win)[1]
  local i = pos + delta
  while i >= 1 and i <= #state.rows do
    if state.rows[i].selectable then
      vim.api.nvim_win_set_cursor(state.win, { i, 0 })
      return
    end
    i = i + delta
  end
end

local function close_win()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.rows = {}
  state.session = nil
  state.diff_qfl = nil
end

local function confirm()
  local row = state.rows[vim.api.nvim_win_get_cursor(state.win)[1]]
  if not row or not row.selectable then return end
  local e = row.entry

  if git('status --porcelain') ~= '' then
    vim.notify('Unstashed changes detected. Stash or commit before checkout.', vim.log.levels.ERROR)
    return
  end

  if e.empty_tree then
    vim.notify('Base is the empty tree (root commit); diff shows full file contents', vim.log.levels.INFO)
  end

  local diff_qfl = state.diff_qfl
  close_win()

  git('checkout ' .. e.checkout_target)
  if vim.v.shell_error ~= 0 then
    vim.notify('git checkout ' .. e.checkout_target .. ' failed', vim.log.levels.ERROR)
    return
  end
  vim.cmd 'checktime'
  diff_qfl(e.base)
end

local function setup_keymaps()
  local opts = { buffer = state.buf, nowait = true, silent = true }
  vim.keymap.set('n', 'j', function() move_cursor(1) end, opts)
  vim.keymap.set('n', 'k', function() move_cursor(-1) end, opts)
  vim.keymap.set('n', '<CR>', confirm, opts)
  vim.keymap.set('n', 'c', function()
    close_win()
    M.close()
  end, opts)
  vim.keymap.set('n', 'q', close_win, opts)
  vim.keymap.set('n', '<Esc>', close_win, opts)
end

local function open_picker(session, diff_qfl)
  state.session = session
  state.diff_qfl = diff_qfl
  state.rows = build_rows(session)

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
    title = ' Tree-diff (enter=checkout+diff, [c]=close session, q=close) ',
    title_pos = 'center',
  })

  vim.wo[state.win].cursorline = true
  vim.wo[state.win].wrap = false
  vim.wo[state.win].winhighlight = 'NormalFloat:Normal'

  render()
  setup_keymaps()
  -- Land on the first selectable row (newest diff entry)
  for i, row in ipairs(state.rows) do
    if row.selectable then
      vim.api.nvim_win_set_cursor(state.win, { i, 0 })
      break
    end
  end
end

local function start(short, diff_qfl)
  local b_sha = git('rev-parse ' .. short)
  local branch = git('branch --show-current')
  local a_sha = git('rev-parse HEAD')
  if b_sha == a_sha then
    vim.notify('Checkpoint is the current HEAD', vim.log.levels.WARN)
    return
  end

  local res, err = require('checkpoint.rangediff').compute(b_sha, a_sha)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local selectable = 0
  for _, e in ipairs(res.entries) do
    if e.status ~= '=' then selectable = selectable + 1 end
  end
  if selectable == 0 then
    vim.notify('No differing commits between checkpoint and HEAD', vim.log.levels.WARN)
    return
  end

  local s = {
    version = 1,
    A = { ref = (branch ~= '' and branch or a_sha), sha = a_sha },
    B = { sha = b_sha },
    merge_base = res.merge_base,
    merge_base_subject = res.merge_base_subject,
    entries = res.entries,
    created = os.date('%Y-%m-%d %H:%M:%S'),
  }
  save(s)
  open_picker(s, diff_qfl)
end

-- <leader>hv: reopen an existing session, else pick a checkpoint and start one
function M.open(diff_qfl)
  if not store_path() then
    vim.notify('Not a git repo', vim.log.levels.ERROR)
    return
  end

  if session_exists() then
    local s = load()
    if s and endpoints_alive(s) then
      open_picker(s, diff_qfl)
      return
    end
    vim.notify('hv session endpoints are gone; clearing', vim.log.levels.WARN)
    clear()
  end

  require('checkpoint').pick(function(short)
    start(short, diff_qfl)
  end)
end

-- <leader>hV: check back out to the starting branch and drop the session
function M.close()
  if not session_exists() then
    vim.notify('No active hv session', vim.log.levels.WARN)
    return
  end
  if git('status --porcelain') ~= '' then
    vim.notify('Unstashed changes detected. Commit or stash before closing.', vim.log.levels.ERROR)
    return
  end

  local s = load()
  git('checkout ' .. s.A.ref)
  if vim.v.shell_error ~= 0 then
    git('checkout ' .. s.A.sha)
    if vim.v.shell_error ~= 0 then
      vim.notify('Could not restore ' .. s.A.ref .. '; session kept', vim.log.levels.ERROR)
      return
    end
  end
  vim.cmd 'checktime'
  clear()
  vim.notify('hv session closed, back on ' .. s.A.ref, vim.log.levels.INFO)
end

function M.setup()
  -- No default keymaps, driven from init.lua via M.open()/M.close()
end

return M
