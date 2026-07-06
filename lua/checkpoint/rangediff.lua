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
--   synthetic base = new^'s tree (all commits below, in their new, folded form)
--                  + this commit in its OLD form (old's patch transplanted via a
--                    real 3-way tree merge: merge-tree --merge-base=old^ new^ old)
--
-- The working tree after checkout is new = same folded commits below + this
-- commit in its NEW form. Everything below is identical on both sides and
-- cancels out, so diff(base, new) is exactly this commit's change-of-change,
-- covering files touched by either version. A file whose transplant conflicts
-- degrades to new^'s version, so it shows the commit's full new patch instead
-- of conflict markers (and never a silently empty diff). The base is a real
-- commit object, so gitgutter can use it for both the quickfix list and
-- per-buffer signs (git show <base>:<file> resolves).
local function synthetic_base(e)
  local out = vim.fn.system('git merge-tree --write-tree --merge-base=' .. e.old .. '^ ' .. e.new .. '^ ' .. e.old)
  local rc = vim.v.shell_error
  if rc ~= 0 and rc ~= 1 then return nil end
  local tree = out:match('^(%x+)')
  if not tree then return nil end

  if rc == 1 then
    -- Conflicted transplant: reset those files to new^'s version
    local index = vim.fn.tempname()
    local env = 'GIT_INDEX_FILE=' .. vim.fn.shellescape(index) .. ' '
    local function giti(cmd)
      local o = vim.fn.system(env .. 'git ' .. cmd)
      return o:gsub('%s+$', ''), vim.v.shell_error
    end

    local _, rerr = giti('read-tree ' .. tree)
    if rerr ~= 0 then return nil end

    local seen = {}
    for mode, path in out:gmatch('(%d+) %x+ %d+[ \t]([^\n]+)') do
      if not seen[path] then
        seen[path] = true
        local blob = vim.fn.system('git rev-parse ' .. e.new .. '^:' .. vim.fn.shellescape(path)):gsub('%s+$', '')
        local uerr
        if vim.v.shell_error == 0 then
          _, uerr = giti('update-index --add --cacheinfo ' .. vim.fn.shellescape(mode .. ',' .. blob .. ',' .. path))
        else
          -- file absent below the commit: drop it so it shows as fully added
          _, uerr = giti('update-index --force-remove ' .. vim.fn.shellescape(path))
        end
        if uerr ~= 0 then
          os.remove(index)
          return nil
        end
      end
    end

    local terr
    tree, terr = giti('write-tree')
    os.remove(index)
    if terr ~= 0 then return nil end
  end

  local commit, cerr = git('commit-tree ' .. tree .. ' -m hv-base')
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
