local M = {}

M._plugins    = {}
M._groups     = {}   -- group name -> { enabled, plugins[] }
M._patches    = {}   -- target plugin name -> list of patch fns
M._schedule   = {}   -- plugin name -> last_update timestamp
M._load_times = {}

M.config = {
  path        = vim.fn.stdpath("data") .. "/garrys/plugins",
  lockfile    = vim.fn.stdpath("config") .. "/garrys.lock",
  schedule    = vim.fn.stdpath("data") .. "/garrys/schedule.json",
  concurrency = 8,
  autoinstall = true,
  strict_deps = false,
  offline     = false,  -- global offline mode
  plugin_dir  = vim.fn.stdpath("config") .. "/lua/plugins",
}

-- ── Public API ─────────────────────────────────────────────────────────────

function M.setup(specs, opts)
  local ok, err = pcall(function()
    if opts then
      M.config = vim.tbl_deep_extend("force", M.config, opts)
    end

    vim.fn.mkdir(M.config.path, "p")
    vim.fn.mkdir(vim.fn.fnamemodify(M.config.schedule, ":h"), "p")

    -- Load update schedule from disk
    M._load_schedule()

    for _, spec in ipairs(specs or {}) do
      if type(spec) == "table" and spec.import then
        -- silently skip, discovery handles it
      else
        local plugin = M._normalize(spec)
        if plugin then
          M._plugins[plugin.name] = plugin
          -- Register group membership
          if plugin.group then
            M._groups[plugin.group] = M._groups[plugin.group] or { enabled = true, plugins = {} }
            table.insert(M._groups[plugin.group].plugins, plugin.name)
          end
        end
      end
    end

    M._discover()
    M._apply_patches()

    if M.config.strict_deps then
      M._validate_deps()
    end

    -- Filter out disabled group plugins
    local active = M._active_plugins()

    require("garrys.loader").load_all(active)

    if M.config.autoinstall then
      M._autoinstall(active)
    end

    -- Check update schedule
    M._check_schedule()
  end)

  if not ok then
    vim.notify("[garrys] setup error: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.plug(spec)
  local ok, err = pcall(function()
    if type(spec) == "string" then spec = { spec } end
    local plugin = M._normalize(spec)
    if plugin then
      M._plugins[plugin.name] = plugin
      if plugin.group then
        M._groups[plugin.group] = M._groups[plugin.group] or { enabled = true, plugins = {} }
        table.insert(M._groups[plugin.group].plugins, plugin.name)
      end
    end
  end)
  if not ok then
    vim.notify("[garrys] invalid spec, skipping: " .. tostring(err), vim.log.levels.WARN)
  end
  return M
end

function M.load(opts)
  M.setup(nil, opts)
end

-- Add a single plugin live (used by :GarryAdd)
function M.add(source)
  if type(source) == "string" then source = { source } end
  local plugin = M._normalize(source)
  if not plugin then return false end
  M._plugins[plugin.name] = plugin
  return plugin
end

-- ── Groups ─────────────────────────────────────────────────────────────────

function M.group_enable(name)
  if not M._groups[name] then
    vim.notify("[garrys] unknown group: " .. name, vim.log.levels.WARN)
    return
  end
  M._groups[name].enabled = true
  -- Load any installed plugins in this group that aren't loaded yet
  local loader = require("garrys.loader")
  for _, pname in ipairs(M._groups[name].plugins) do
    local plugin = M._plugins[pname]
    if plugin and not plugin._loaded then
      loader.inject(plugin)
    end
  end
  vim.notify("[garrys] group '" .. name .. "' enabled", vim.log.levels.INFO)
end

function M.group_disable(name)
  if not M._groups[name] then
    vim.notify("[garrys] unknown group: " .. name, vim.log.levels.WARN)
    return
  end
  M._groups[name].enabled = false
  vim.notify("[garrys] group '" .. name .. "' disabled (restart to take effect)", vim.log.levels.INFO)
end

function M.group_list()
  local result = {}
  for name, group in pairs(M._groups) do
    table.insert(result, {
      name    = name,
      enabled = group.enabled,
      count   = #group.plugins,
    })
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

-- Returns only plugins that belong to enabled groups (or no group)
function M._active_plugins()
  local active = {}
  for name, plugin in pairs(M._plugins) do
    local group = plugin.group
    if not group or (M._groups[group] and M._groups[group].enabled) then
      active[name] = plugin
    end
  end
  return active
end

-- ── Patches / Stacking ─────────────────────────────────────────────────────

-- Apply extends+patch specs to their target plugins
function M._apply_patches()
  for _, plugin in pairs(M._plugins) do
    if plugin.extends then
      local target_name = plugin.extends:match("[^/]+$")
      local target      = M._plugins[target_name]
      if target and plugin.patch then
        -- Apply patch fn to target's opts
        local ok, result = pcall(plugin.patch, vim.deepcopy(target.opts or {}))
        if ok and result then
          target.opts = result
        else
          vim.notify("[garrys] patch failed for " .. plugin.name .. ": " .. tostring(result), vim.log.levels.WARN)
        end
        -- The extending plugin itself doesn't need to install separately
        -- if it has no source beyond its extends target
        if not plugin._has_own_source then
          M._plugins[plugin.name] = nil
        end
      elseif not target then
        vim.notify("[garrys] extends target '" .. plugin.extends .. "' not found", vim.log.levels.WARN)
      end
    end
  end
end

-- ── Schedule / Auto-update ─────────────────────────────────────────────────

local INTERVALS = {
  daily   = 86400,
  weekly  = 604800,
  monthly = 2592000,
}

function M._load_schedule()
  local f = io.open(M.config.schedule, "r")
  if not f then return end
  local raw = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, raw)
  if ok and data then M._schedule = data end
end

function M._save_schedule()
  local f = io.open(M.config.schedule, "w")
  if not f then return end
  f:write(vim.json.encode(M._schedule))
  f:close()
end

function M._check_schedule()
  local now     = os.time()
  local due     = {}

  for _, plugin in pairs(M._plugins) do
    if plugin.update and not plugin.pin then
      local interval   = INTERVALS[plugin.update]
      local last_check = M._schedule[plugin.name] or 0
      if interval and (now - last_check) >= interval then
        table.insert(due, plugin)
      end
    end
  end

  if #due == 0 then return end

  -- Schedule updates after startup
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.defer_fn(function()
        local git = require("garrys.git")
        local now_ts = os.time()

        vim.notify("[garrys] auto-updating " .. #due .. " plugin(s)...", vim.log.levels.INFO)

        for _, plugin in ipairs(due) do
          git.pull(plugin.path, function(ok, err)
            vim.schedule(function()
              if ok then
                M._schedule[plugin.name] = now_ts
                M._save_schedule()
                vim.notify("[garrys] auto-updated " .. plugin.name, vim.log.levels.INFO)
              else
                vim.notify("[garrys] auto-update failed for " .. plugin.name, vim.log.levels.WARN)
              end
            end)
          end)
        end
      end, 3000)  -- 3 seconds after startup
    end,
  })
end

-- ── Normalize ──────────────────────────────────────────────────────────────

function M._normalize(spec)
  if spec == nil then return nil end
  if type(spec) ~= "table" and type(spec) ~= "string" then return nil end
  if type(spec) == "string" then spec = { spec } end
  if spec.import then return nil end

  local source = spec[1]

  if not source and spec.url then
    source = spec.url:match("([^/]+/[^/%.]+)%.git$") or spec.url
  end

  if not source and spec.dir then
    pcall(function()
      if vim.loop.fs_stat(spec.dir) then
        vim.opt.rtp:prepend(spec.dir)
        local after = spec.dir .. "/after"
        if vim.loop.fs_stat(after) then vim.opt.rtp:append(after) end
        if spec.init then pcall(spec.init) end
      else
        vim.notify("[garrys] local dir not found: " .. spec.dir, vim.log.levels.WARN)
      end
    end)
    return nil
  end

  -- Pure patch spec — no own source, just extends another plugin
  local is_patch = spec.extends ~= nil and source == nil
  if is_patch then
    return {
      name            = spec.name or (spec.extends:match("[^/]+$") .. "-patch"),
      extends         = spec.extends,
      patch           = spec.patch or nil,
      _has_own_source = false,
      _loaded         = false,
      group           = spec.group or nil,
    }
  end

  if not source then return nil end

  if spec.cond ~= nil then
    local ok, result = pcall(function()
      return type(spec.cond) == "function" and spec.cond() or spec.cond
    end)
    if not ok or not result then return nil end
  end

  local name = spec.name or source:match("[^/]+$")
  if not name or name == "" then return nil end

  local u        = require("garrys.util")
  local raw_deps = spec.dependencies or spec.depends or spec.dep or {}
  local dep_clean = {}

  for _, d in ipairs(raw_deps) do
    if type(d) == "string" then
      table.insert(dep_clean, d)
    elseif type(d) == "table" and d[1] then
      table.insert(dep_clean, d[1])
      local dep_name = d[1]:match("[^/]+$")
      if dep_name and not M._plugins[dep_name] then
        local sub = M._normalize(d)
        if sub then M._plugins[sub.name] = sub end
      end
    end
  end

  -- Resolve branch/tag into a git ref
  local git_ref = spec.tag or spec.branch or nil

  return {
    name            = name,
    source          = source,
    url             = spec.url or ("https://github.com/" .. source .. ".git"),
    path            = u.plugin_path(M.config.path, name),
    lazy            = spec.lazy   or false,
    event           = spec.event  or nil,
    cmd             = spec.cmd    or nil,
    ft              = spec.ft     or nil,
    keys            = spec.keys   or nil,
    cond            = spec.cond   or nil,
    pin             = spec.pin    or false,
    offline         = spec.offline or M.config.offline,
    group           = spec.group  or nil,
    update          = spec.update or nil,  -- "daily" | "weekly" | "monthly"
    branch          = spec.branch or nil,
    tag             = spec.tag    or nil,
    git_ref         = git_ref,
    extends         = spec.extends or nil,
    patch           = spec.patch   or nil,
    _has_own_source = true,
    dep             = dep_clean,
    on              = spec.on or spec.config or nil,
    init            = spec.init   or nil,
    make            = spec.make or spec.build or nil,
    opts            = spec.opts   or {},
    _loaded         = false,
  }
end

-- ── Discovery ──────────────────────────────────────────────────────────────

function M._discover()
  local dir = M.config.plugin_dir
  if not vim.loop.fs_stat(dir) then return end

  local handle = vim.loop.fs_scandir(dir)
  if not handle then return end

  while true do
    local fname, ftype = vim.loop.fs_scandir_next(handle)
    if not fname then break end
    if ftype == "file" and fname:match("%.lua$") then
      local mod = "plugins." .. fname:gsub("%.lua$", "")
      local ok, result = pcall(require, mod)
      if ok and type(result) == "table" then
        for _, spec in ipairs(result) do
          if type(spec) == "table" and not spec.import then
            local plugin = M._normalize(spec)
            if plugin and not M._plugins[plugin.name] then
              M._plugins[plugin.name] = plugin
              if plugin.group then
                M._groups[plugin.group] = M._groups[plugin.group] or { enabled = true, plugins = {} }
                table.insert(M._groups[plugin.group].plugins, plugin.name)
              end
            end
          end
        end
      elseif not ok then
        vim.notify("[garrys] skipping " .. mod .. ": " .. tostring(result), vim.log.levels.WARN)
      end
    end
  end
end

function M._validate_deps()
  local warnings = {}
  for _, plugin in pairs(M._plugins) do
    for _, dep in ipairs(plugin.dep or {}) do
      local dep_name = dep:match("[^/]+$")
      if dep_name and not M._plugins[dep_name] then
        table.insert(warnings, string.format("'%s' needs '%s'", plugin.name, dep))
      end
    end
  end
  if #warnings > 0 then
    vim.notify("[garrys] dep warnings:\n  " .. table.concat(warnings, "\n  "), vim.log.levels.WARN)
  end
end

-- ── Autoinstall ────────────────────────────────────────────────────────────

function M._autoinstall(plugins)
  local u       = require("garrys.util")
  local missing = {}

  for _, plugin in pairs(plugins) do
    if plugin._has_own_source ~= false
      and not plugin.offline
      and not u.is_installed(plugin.path) then
      table.insert(missing, plugin)
    end
  end

  if #missing == 0 then return end

  table.sort(missing, function(a, b) return a.name < b.name end)

  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      local ok, err = pcall(function()
        local git    = require("garrys.git")
        local _ui    = require("garrys.ui")
        local loader = require("garrys.loader")

        _ui.open()
        _ui.set_total(#missing)

        local done = 0; local active = 0; local i = 1

        local function clone_plugin(plugin, callback)
          local args = { "git", "clone", "--depth=1", "--filter=blob:none" }
          -- Checkout specific branch or tag if specified
          if plugin.git_ref then
            vim.list_extend(args, { "--branch", plugin.git_ref })
          end
          vim.list_extend(args, { plugin.url, plugin.path })
          vim.system(args, { text = true }, function(result)
            callback(result.code == 0, result.stderr)
          end)
        end

        local function dispatch()
          while active < M.config.concurrency and i <= #missing do
            local plugin = missing[i]; i = i + 1; active = active + 1
            _ui.set_status(plugin.name, "installing...")

            clone_plugin(plugin, function(clone_ok, clone_err)
              active = active - 1; done = done + 1
              vim.schedule(function()
                if clone_ok then
                  _ui.set_status(plugin.name, "✔ installed")
                  pcall(loader.inject, plugin)
                  if plugin.make then pcall(u.run_build, plugin) end
                else
                  -- Retry once without branch/tag in case ref doesn't exist
                  _ui.set_status(plugin.name, "⟳ retrying...")
                  local retry_plugin = vim.tbl_extend("force", plugin, { git_ref = nil })
                  clone_plugin(retry_plugin, function(rok, rerr)
                    vim.schedule(function()
                      if rok then
                        _ui.set_status(plugin.name, "✔ installed")
                        pcall(loader.inject, plugin)
                      else
                        _ui.set_status(plugin.name, "✘ " .. (rerr or clone_err or "failed"):gsub("\n", " "))
                      end
                    end)
                  end)
                end
                if done == #missing then _ui.finish() else dispatch() end
              end)
            end)
          end
        end

        dispatch()
      end)

      if not ok then
        vim.notify("[garrys] autoinstall error: " .. tostring(err), vim.log.levels.ERROR)
      end
    end,
  })
end

-- ── Helpers ────────────────────────────────────────────────────────────────

function M.has_missing()
  local u = require("garrys.util")
  for _, plugin in pairs(M._plugins) do
    if plugin._has_own_source ~= false and not u.is_installed(plugin.path) then
      return true
    end
  end
  return false
end

function M.get(name)
  return M._plugins[name]
end

return M
