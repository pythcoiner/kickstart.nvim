-- Tree-diff engine: turn two commits into an ordered range-diff series.
-- Pure logic (no windows/buffers); shells out to git, returns data + error strings.
local M = {}

local EMPTY_TREE = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
-- Which side of an entry is loaded into the working tree on checkout
local CHECKOUT = { ['!'] = 'new', ['>'] = 'new', ['<'] = 'old', ['='] = 'new' }

local function git(cmd)
  local out = vim.fn.system('git ' .. cmd)
  return out:gsub('%s+$', ''), vim.v.shell_error
end

-- Parent of sha, or the empty tree (root commit). Second return flags the empty tree.
local function parent_or_empty(sha)
  if not sha then return nil, false end
  local _, err = git('rev-parse --verify --quiet ' .. sha .. '^')
  if err ~= 0 then
    return EMPTY_TREE, true
  end
  return sha .. '^', false
end

-- Parse only range-diff header lines: "N:  <sha>  OP  M:  <sha>  <subject>".
-- An all-dash sha means the entry is one-sided; store it as nil.
local function parse_headers(text)
  local entries = {}
  for line in text:gmatch('[^\n]+') do
    local _, old, status, _, new, subject = line:match('^%s*(%S+):%s+(%S+)%s+([=!<>])%s+(%S+):%s+(%S+)%s*(.*)$')
    if status then
      if old:match('^%-+$') then old = nil end
      if new:match('^%-+$') then new = nil end
      table.insert(entries, { status = status, old = old, new = new, subject = subject })
    end
  end
  return entries
end

-- Show, per entry, what changed since the checkpoint. For a changed (!) commit that
-- is the delta between the checkpoint-side version (old) and the current one (new);
-- for added (>) / dropped (<) it is that commit's own patch (checkout_target vs its
-- parent, or the empty tree for a root commit).
-- Why a synthetic base: for a changed (!) entry we want to compare the commit
-- before edit with the commit after edit. But old and new are whole-branch
-- snapshots, not the commit alone: their trees also differ by every fixup folded
-- into the commits below this one, so `git diff old new` drags all of those in,
-- and `git diff new^ new` shows the whole commit instead of just its edit. The
-- revision that isolates the edit exists nowhere in history, so we build it:
--
--   synthetic base = new's tree (all commits below, in their new, folded form)
--                  + this commit in its OLD form (old's patch transplanted onto
--                    new^'s content via 3-way merge, file by file)
--
-- The working tree after checkout is new = same folded commits below + this
-- commit in its NEW form. Everything below is identical on both sides and
-- cancels out, so diff(base, new) is exactly this commit's change-of-change.
-- It is a real commit object, so gitgutter can use it as diff base for both
-- the quickfix list and per-buffer signs (git show <base>:<file> resolves).
local function synthetic_base(e)
  local own = git('diff --name-only ' .. e.new .. '^ ' .. e.new)
  if own == '' then return nil end

  local index = vim.fn.tempname()
  local env = 'GIT_INDEX_FILE=' .. vim.fn.shellescape(index) .. ' '
  local function giti(cmd)
    local out = vim.fn.system(env .. 'git ' .. cmd)
    return out:gsub('%s+$', ''), vim.v.shell_error
  end

  local function show_to(rev, file, dst)
    -- missing on that side (file added/deleted by the commit) -> empty content
    local content = vim.fn.system('git show ' .. rev .. ':' .. vim.fn.shellescape(file))
    if vim.v.shell_error ~= 0 then content = '' end
    local f = io.open(dst, 'w')
    if not f then return false end
    f:write(content)
    f:close()
    return true
  end

  local _, rerr = giti('read-tree ' .. e.new)
  if rerr ~= 0 then return nil end

  local cur, base, other = vim.fn.tempname(), vim.fn.tempname(), vim.fn.tempname()
  for file in own:gmatch('[^\n]+') do
    if not (show_to(e.new .. '^', file, cur) and show_to(e.old .. '^', file, base) and show_to(e.old, file, other)) then
      return nil
    end
    local merged = vim.fn.system('git merge-file -p ' .. cur .. ' ' .. base .. ' ' .. other)
    if vim.v.shell_error ~= 0 then
      -- conflicting transplant: keep old's whole version of this file
      merged = vim.fn.system('git show ' .. e.old .. ':' .. vim.fn.shellescape(file))
      if vim.v.shell_error ~= 0 then merged = '' end
    end
    local f = io.open(cur, 'w')
    if not f then return nil end
    f:write(merged)
    f:close()
    local sha = vim.fn.system('git hash-object -w ' .. cur):gsub('%s+$', '')
    if vim.v.shell_error ~= 0 then return nil end
    local mode = vim.fn.system('git ls-tree ' .. e.new .. ' -- ' .. vim.fn.shellescape(file)):match('^(%d+)') or '100644'
    local _, uerr = giti('update-index --add --cacheinfo ' .. mode .. ',' .. sha .. ',' .. vim.fn.shellescape(file))
    if uerr ~= 0 then return nil end
  end

  local tree, terr = giti('write-tree')
  if terr ~= 0 then return nil end
  local commit, cerr = giti('commit-tree ' .. tree .. ' -m hv-base')
  os.remove(index)
  os.remove(cur)
  os.remove(base)
  os.remove(other)
  if cerr ~= 0 then return nil end
  return commit
end

local function resolve(e)
  e.checkout_target = e[CHECKOUT[e.status]]
  if e.status == '!' then
    e.base = synthetic_base(e) or e.old
  else
    e.base, e.empty_tree = parent_or_empty(e.checkout_target)
  end
end

function M.compute(old_ref, new_ref, base_override)
  local spec = base_override
    and (base_override .. ' ' .. old_ref .. ' ' .. new_ref)
    or (old_ref .. '...' .. new_ref)

  local out, err = git('range-diff --no-color ' .. spec)
  if err ~= 0 then
    return nil, 'git range-diff failed: ' .. out
  end

  local entries = parse_headers(out)
  for _, e in ipairs(entries) do
    resolve(e)
  end

  local merge_base = git('merge-base ' .. old_ref .. ' ' .. new_ref)
  local merge_base_subject = merge_base ~= '' and git('log -1 --format=%s ' .. merge_base) or ''

  return {
    merge_base = merge_base,
    merge_base_subject = merge_base_subject,
    entries = entries,
  }
end

return M
