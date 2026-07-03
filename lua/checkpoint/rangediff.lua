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

-- Always diff the checked-out commit against its own parent, i.e. show just this
-- commit's own patch. Root commits have no parent, so fall back to the empty tree.
local function resolve(e)
  e.checkout_target = e[CHECKOUT[e.status]]
  e.base, e.empty_tree = parent_or_empty(e.checkout_target)
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
