local M = {}
local state = {
  buf = nil,
  win = nil,
  features = {},
  selected = {},
  extra = {},
  source_buf = nil,
  client_id = nil,
  root_dir = nil,
  cargo = {},
  package = nil,
  packages = {},
  request = 0,
}

local function get_window_opts()
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.7)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1
  return { width = width, height = height, col = col, row = row }
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = {}
  for i, feature in ipairs(state.features) do
    local prefix = state.selected[feature] and '[x] ' or '[ ] '
    lines[i] = prefix .. feature
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function move_cursor(delta)
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local new_row = math.max(1, math.min(#state.features, pos[1] + delta))
  vim.api.nvim_win_set_cursor(state.win, { new_row, 0 })
end

local function toggle_selection()
  local pos = vim.api.nvim_win_get_cursor(state.win)
  local feature = state.features[pos[1]]
  if feature then
    if state.selected[feature] then
      state.selected[feature] = nil
    else
      state.selected[feature] = true
    end
    render()
    move_cursor(1)
  end
end

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.features = {}
  state.selected = {}
  state.extra = {}
  state.source_buf = nil
  state.client_id = nil
  state.root_dir = nil
  state.cargo = {}
  state.package = nil
  state.packages = {}
end

local function settings_path(root_dir)
  local dir = vim.fn.stdpath 'config' .. '/rust/feature_flags'
  return dir, dir .. '/' .. vim.fs.basename(vim.fs.normalize(root_dir))
end

local function persist_cargo(root_dir, cargo)
  local dir, path = settings_path(root_dir)
  local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, dir, 'p')
  if not mkdir_ok or (mkdir_result == 0 and vim.fn.isdirectory(dir) == 0) then
    return false, 'Failed to create Cargo feature settings directory: ' .. dir
  end

  local encode_ok, encoded = pcall(vim.json.encode, {
    features = cargo.features,
    noDefaultFeatures = cargo.noDefaultFeatures,
  })
  if not encode_ok then
    return false, 'Failed to encode Cargo feature settings: ' .. encoded
  end

  local write_ok, write_result = pcall(vim.fn.writefile, { encoded }, path)
  if not write_ok or write_result ~= 0 then
    return false, 'Failed to write Cargo feature settings: ' .. path
  end
  return true
end

local function valid_cargo(cargo)
  if cargo.features ~= nil and cargo.features ~= 'all' then
    if type(cargo.features) ~= 'table' or not vim.islist(cargo.features) then
      return false
    end
    for _, feature in ipairs(cargo.features) do
      if type(feature) ~= 'string' then
        return false
      end
    end
  end
  return cargo.noDefaultFeatures == nil or type(cargo.noDefaultFeatures) == 'boolean'
end

local function package_selection(package, cargo)
  local features = vim.tbl_keys(package.features)
  table.sort(features)
  local selected = {}
  if cargo.features == 'all' then
    for _, feature in ipairs(features) do
      selected[feature] = true
    end
  elseif type(cargo.features) == 'table' then
    local package_prefix = package.name .. '/'
    for _, configured_feature in ipairs(cargo.features) do
      local feature = configured_feature
      if feature:sub(1, #package_prefix) == package_prefix then
        feature = feature:sub(#package_prefix + 1)
      end
      if package.features[feature] then
        selected[feature] = true
      end
    end
  end
  if cargo.features ~= 'all' and package.features.default and cargo.noDefaultFeatures ~= true then
    selected.default = true
  end
  return features, selected
end

-- Every workspace member's features, shown as `package/feature`
local function workspace_selection(packages, cargo)
  local features = {}
  local selected = {}
  local shown = {}
  for _, package in ipairs(packages) do
    for feature in pairs(package.features) do
      local name = package.name .. '/' .. feature
      table.insert(features, name)
      shown[name] = true
      if cargo.features == 'all' or (feature == 'default' and cargo.noDefaultFeatures ~= true) then
        selected[name] = true
      end
    end
  end
  table.sort(features)

  -- Saved entries matching no member feature (e.g. dependency features) are kept as is
  local extra = {}
  if type(cargo.features) == 'table' then
    for _, configured in ipairs(cargo.features) do
      local matched = shown[configured] == true
      if matched then
        selected[configured] = true
      elseif not configured:find('/', 1, true) then
        for _, package in ipairs(packages) do
          local name = package.name .. '/' .. configured
          if shown[name] then
            selected[name] = true
            matched = true
          end
        end
      end
      if not matched then
        table.insert(extra, configured)
      end
    end
  end
  return features, selected, extra
end

local function confirm()
  if
    not state.source_buf
    or not vim.api.nvim_buf_is_valid(state.source_buf)
    or not state.client_id
    or not vim.lsp.buf_is_attached(state.source_buf, state.client_id)
  then
    close()
    vim.notify('No active rust-analyzer client', vim.log.levels.ERROR)
    return
  end

  local cargo = state.cargo
  if #state.packages > 1 then
    local features = vim.list_extend({}, state.extra)
    for _, feature in ipairs(state.features) do
      if state.selected[feature] then
        table.insert(features, feature)
      end
    end
    table.sort(features)
    cargo.features = features
    cargo.noDefaultFeatures = true
  else
    local features = {}
    for _, feature in ipairs(state.features) do
      if feature ~= 'default' and state.selected[feature] then
        table.insert(features, feature)
      end
    end
    cargo.features = features
    if state.package.features.default then
      cargo.noDefaultFeatures = not state.selected.default
    end
  end
  local persisted, err = persist_cargo(state.root_dir, cargo)
  if not persisted then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  local source_buf = state.source_buf
  close()

  vim.api.nvim_buf_call(source_buf, function()
    require('rustaceanvim.lsp').set_config { cargo = cargo }
  end)
end

local function setup_keymaps()
  local opts = { buffer = state.buf, nowait = true, silent = true }

  vim.keymap.set('n', 'j', function()
    move_cursor(1)
  end, opts)
  vim.keymap.set('n', 'k', function()
    move_cursor(-1)
  end, opts)
  vim.keymap.set('n', '<Space>', toggle_selection, opts)
  vim.keymap.set('n', '<CR>', confirm, opts)
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

local function open_picker(package, packages, cargo, bufnr, client_id, root_dir)
  close()
  local title = package.name
  if #packages > 1 then
    title = vim.fs.basename(root_dir)
    state.features, state.selected, state.extra = workspace_selection(packages, cargo)
  else
    state.features, state.selected = package_selection(package, cargo)
  end
  if #state.features == 0 then
    vim.notify('No Cargo features found for ' .. title, vim.log.levels.ERROR)
    return
  end

  state.source_buf = bufnr
  state.client_id = client_id
  state.root_dir = root_dir
  state.cargo = vim.deepcopy(cargo)
  state.package = package
  state.packages = packages
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
    title = ' Cargo features: ' .. title .. ' ',
    title_pos = 'center',
    footer = ' Space=toggle, Enter=apply, q=cancel ',
    footer_pos = 'center',
  })

  vim.wo[state.win].cursorline = true
  vim.wo[state.win].wrap = false
  vim.wo[state.win].winhighlight = 'NormalFloat:Normal'

  render()
  setup_keymaps()
end

local function workspace_packages(metadata)
  local workspace_members = {}
  for _, id in ipairs(metadata.workspace_members or {}) do
    workspace_members[id] = true
  end
  return vim.tbl_filter(function(candidate)
    return workspace_members[candidate.id] == true
  end, metadata.packages or {})
end

-- A `package/feature` saved from another checkout makes `cargo metadata` fail, and rust-analyzer loses the dependency graph
local function drop_stale_features(root_dir, features, path)
  local result = vim
    .system({ 'cargo', 'metadata', '--no-deps', '--format-version', '1' }, {
      cwd = root_dir,
      text = true,
    })
    :wait()
  local ok, metadata = pcall(vim.json.decode, result.stdout or '')
  if result.code ~= 0 or not ok or type(metadata) ~= 'table' then
    vim.notify('Cargo metadata failed, cannot check Cargo feature settings: ' .. path, vim.log.levels.WARN)
    return features
  end

  local package_features = {}
  for _, package in ipairs(workspace_packages(metadata)) do
    package_features[package.name] = package.features
  end
  local kept = {}
  local stale = {}
  for _, feature in ipairs(features) do
    local package_name, package_feature = feature:match '^([^/]+)/(.+)$'
    if package_name and package_features[package_name] and package_features[package_name][package_feature] == nil then
      table.insert(stale, feature)
    else
      table.insert(kept, feature)
    end
  end
  if #stale > 0 then
    vim.notify('Ignoring Cargo features missing from the workspace (' .. path .. '): ' .. table.concat(stale, ', '), vim.log.levels.WARN)
  end
  return kept
end

function M.settings(root_dir, default_settings)
  local settings = vim.deepcopy(default_settings or {})
  if not root_dir then
    return settings
  end
  local _, path = settings_path(root_dir)
  if vim.fn.filereadable(path) == 0 then
    if vim.fn.getftype(path) ~= '' then
      vim.notify('Cannot read Cargo feature settings: ' .. path, vim.log.levels.ERROR)
    end
    return settings
  end

  local read_ok, lines = pcall(vim.fn.readfile, path)
  if not read_ok then
    vim.notify('Cannot read Cargo feature settings: ' .. path, vim.log.levels.ERROR)
    return settings
  end

  local decode_ok, cargo = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decode_ok or type(cargo) ~= 'table' or not valid_cargo(cargo) then
    vim.notify('Invalid Cargo feature settings JSON: ' .. path, vim.log.levels.ERROR)
    return settings
  end

  local rust_analyzer = settings['rust-analyzer'] or {}
  local cargo_settings = rust_analyzer.cargo or {}
  rust_analyzer.cargo = cargo_settings
  settings['rust-analyzer'] = rust_analyzer
  if type(cargo.features) == 'table' then
    cargo_settings.features = drop_stale_features(root_dir, cargo.features, path)
  elseif cargo.features ~= nil then
    cargo_settings.features = cargo.features
  end
  if cargo.noDefaultFeatures ~= nil then
    cargo_settings.noDefaultFeatures = cargo.noDefaultFeatures
  end
  return settings
end

local function is_path_prefix(path, prefix)
  return path == prefix or path:sub(1, #prefix + 1) == prefix .. '/'
end

local function find_package(metadata, filename)
  local package
  local prefix_length = 0
  for _, candidate in ipairs(metadata.packages or {}) do
    local manifest_dir = vim.fs.dirname(vim.fs.normalize(candidate.manifest_path))
    if is_path_prefix(filename, manifest_dir) and #manifest_dir > prefix_length then
      package = candidate
      prefix_length = #manifest_dir
    end
  end
  return package
end

function M.open(bufnr, client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  if not client or client.name ~= 'rust-analyzer' or not vim.lsp.buf_is_attached(bufnr, client_id) then
    vim.notify('No active rust-analyzer client', vim.log.levels.ERROR)
    return
  end

  local filename = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  local root_dir = client.root_dir or client.config.root_dir
  root_dir = root_dir and vim.fs.normalize(root_dir) or nil
  local root_length = root_dir and is_path_prefix(filename, root_dir) and #root_dir or 0
  if root_length == 0 then
    root_dir = nil
  end
  for _, workspace in ipairs(client.workspace_folders or {}) do
    local workspace_root = vim.fs.normalize(vim.uri_to_fname(workspace.uri))
    if is_path_prefix(filename, workspace_root) and #workspace_root > root_length then
      root_dir = workspace_root
      root_length = #workspace_root
    end
  end
  if not root_dir then
    vim.notify('No active rust-analyzer client with a project root', vim.log.levels.ERROR)
    return
  end

  state.request = state.request + 1
  local request = state.request
  vim.system({ 'cargo', 'metadata', '--no-deps', '--format-version', '1' }, {
    cwd = root_dir,
    text = true,
  }, function(result)
    vim.schedule(function()
      if request ~= state.request then
        return
      end
      if result.code ~= 0 then
        local message = vim.trim(result.stderr or '')
        vim.notify('Cargo metadata failed' .. (message ~= '' and ': ' .. message or ''), vim.log.levels.ERROR)
        return
      end

      local ok, metadata = pcall(vim.json.decode, result.stdout)
      if not ok or type(metadata) ~= 'table' then
        vim.notify('Failed to decode Cargo metadata', vim.log.levels.ERROR)
        return
      end

      local package = find_package(metadata, filename)
      if not package then
        vim.notify('No Cargo package matches the current Rust buffer', vim.log.levels.ERROR)
        return
      end

      local active_client = vim.lsp.get_client_by_id(client_id)
      if not vim.api.nvim_buf_is_valid(bufnr) or not active_client or not vim.lsp.buf_is_attached(bufnr, client_id) then
        vim.notify('No active rust-analyzer client', vim.log.levels.ERROR)
        return
      end

      local packages = workspace_packages(metadata)
      local cargo = vim.tbl_get(active_client.settings or {}, 'rust-analyzer', 'cargo') or {}
      open_picker(package, packages, cargo, bufnr, client_id, root_dir)
    end)
  end)
end

return M
