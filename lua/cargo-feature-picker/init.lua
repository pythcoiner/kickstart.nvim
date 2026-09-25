local M = {}
local state = {
  buf = nil,
  win = nil,
  features = {},
  selected = {},
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

local function add_feature(features, seen, feature)
  if not seen[feature] then
    table.insert(features, feature)
    seen[feature] = true
  end
end

local function workspace_features()
  local features = {}
  local seen = {}
  local current = state.package
  local current_prefix = current.name .. '/'

  if state.cargo.features == 'all' then
    for _, package in ipairs(state.packages) do
      if package.id ~= current.id then
        for feature in pairs(package.features) do
          add_feature(features, seen, package.name .. '/' .. feature)
        end
      end
    end
  elseif type(state.cargo.features) == 'table' then
    for _, feature in ipairs(state.cargo.features) do
      if feature:sub(1, #current_prefix) ~= current_prefix then
        if current.features[feature] then
          for _, package in ipairs(state.packages) do
            if package.id ~= current.id and package.features[feature] then
              add_feature(features, seen, package.name .. '/' .. feature)
            end
          end
        else
          add_feature(features, seen, feature)
        end
      end
    end
  end

  if state.cargo.noDefaultFeatures ~= true then
    for _, package in ipairs(state.packages) do
      if package.id ~= current.id and package.features.default then
        add_feature(features, seen, package.name .. '/default')
      end
    end
  end

  for _, feature in ipairs(state.features) do
    if state.selected[feature] then
      add_feature(features, seen, current.name .. '/' .. feature)
    end
  end
  table.sort(features)
  return features
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
    cargo.features = workspace_features()
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
  state.features = vim.tbl_keys(package.features)
  table.sort(state.features)
  if #state.features == 0 then
    vim.notify('No Cargo features found for ' .. package.name, vim.log.levels.ERROR)
    return
  end

  state.selected = {}
  if cargo.features == 'all' then
    for _, feature in ipairs(state.features) do
      state.selected[feature] = true
    end
  elseif type(cargo.features) == 'table' then
    local package_prefix = package.name .. '/'
    for _, configured_feature in ipairs(cargo.features) do
      local feature = configured_feature
      if feature:sub(1, #package_prefix) == package_prefix then
        feature = feature:sub(#package_prefix + 1)
      end
      if package.features[feature] then
        state.selected[feature] = true
      end
    end
  end
  if cargo.features ~= 'all' and package.features.default and cargo.noDefaultFeatures ~= true then
    state.selected.default = true
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
    title = ' Cargo features: ' .. package.name .. ' ',
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
  if cargo.features ~= nil then
    cargo_settings.features = vim.deepcopy(cargo.features)
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

      local workspace_members = {}
      for _, id in ipairs(metadata.workspace_members or {}) do
        workspace_members[id] = true
      end
      local packages = vim.tbl_filter(function(candidate)
        return workspace_members[candidate.id] == true
      end, metadata.packages or {})
      local cargo = vim.tbl_get(active_client.settings or {}, 'rust-analyzer', 'cargo') or {}
      open_picker(package, packages, cargo, bufnr, client_id, root_dir)
    end)
  end)
end

return M
