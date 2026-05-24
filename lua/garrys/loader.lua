local M = {}
local u = require("garrys.util")

-- Sync package.path so nested requires work inside plugins
local function sync_package_path(path)
  local lua_path = path .. "/lua/?.lua"
  local lua_init = path .. "/lua/?/init.lua"
  if not package.path:find(lua_path, 1, true) then
    package.path = lua_path .. ";" .. lua_init .. ";" .. package.path
  end
end

local function sync_package_cpath(path)
  local cpath = path .. "/lua/?.so"
  if not package.cpath:find(cpath, 1, true) then
    package.cpath = cpath .. ";" .. package.cpath
  end
end

function M.inject(plugin)
  -- Always check disk first — never run config on uninstalled plugin
  if not u.is_installed(plugin.path) then return end

  -- Run init before load (lazy.nvim compat)
  if plugin.init then
    local ok, err = pcall(plugin.init)
    if not ok then
      u.warn("init failed for " .. plugin.name .. ": " .. tostring(err))
    end
  end

  -- Add to rtp
  vim.opt.rtp:prepend(plugin.path)
  local after = plugin.path .. "/after"
  if u.is_installed(after) then vim.opt.rtp:append(after) end

  -- Sync package paths
  sync_package_path(plugin.path)
  sync_package_cpath(plugin.path)

  -- Source plugin/ runtime files
  local plugin_dir = plugin.path .. "/plugin"
  if u.is_installed(plugin_dir) then
    local files = vim.fn.glob(plugin_dir .. "/*.{vim,lua}", false, true)
    for _, f in ipairs(files) do
      local ok, err = pcall(vim.cmd, "source " .. vim.fn.fnameescape(f))
      if not ok then
        u.warn("source failed for " .. plugin.name .. ": " .. tostring(err))
      end
    end
  end

  -- Run config — `on` is the garrys field, also accept `config` (lazy compat)
  if plugin.on then
    local ok, err = pcall(plugin.on, plugin.opts)
    if not ok then
      u.err("config failed for " .. plugin.name .. ": " .. err)
    end
  elseif plugin.opts and next(plugin.opts) ~= nil then
    -- Auto-setup if opts provided but no explicit config
    -- Try common module name patterns
    local candidates = {
      plugin.name,
      plugin.name:gsub("%.nvim$", ""),
      plugin.name:gsub("%-nvim$", ""),
      plugin.name:gsub("nvim%-", ""),
    }
    for _, mod_name in ipairs(candidates) do
      local ok, mod = pcall(require, mod_name)
      if ok and type(mod) == "table" and mod.setup then
        local setup_ok, setup_err = pcall(mod.setup, plugin.opts)
        if not setup_ok then
          u.warn("auto-setup failed for " .. plugin.name .. ": " .. tostring(setup_err))
        end
        break
      end
    end
  end

  plugin._loaded = true

  -- Track profile time
  local ok, prof = pcall(require, "garrys.profile")
  if ok then prof.stop(plugin.name) end
end

function M.register(plugin)
  local function load_once()
    if plugin._loaded then return end
    -- If not installed yet, queue for install then load after
    if not u.is_installed(plugin.path) then
      vim.notify("[garrys] " .. plugin.name .. " not installed yet — run :GarryInstall", vim.log.levels.WARN)
      return
    end
    M.inject(plugin)
  end

  -- Lazy by event
  if plugin.event then
    local events    = type(plugin.event) == "string" and { plugin.event } or plugin.event
    local valid     = {}
    local very_lazy = false

    for _, ev in ipairs(events) do
      if ev == "VeryLazy" then
        -- Synthetic event (lazy.nvim compat) — fires after UI is ready
        very_lazy = true
      else
        local ok = pcall(vim.api.nvim_create_autocmd, ev, { once = true, callback = function() end })
        if ok then table.insert(valid, ev)
        else u.warn("unknown event '" .. ev .. "' for " .. plugin.name) end
      end
    end

    if very_lazy then
      vim.api.nvim_create_autocmd("UIEnter", {
        once     = true,
        callback = function()
          vim.defer_fn(load_once, 100)
        end,
      })
    end

    if #valid > 0 then
      vim.api.nvim_create_autocmd(valid, { once = true, callback = load_once })
    end
  end

  -- Lazy by command
  if plugin.cmd then
    local cmds = type(plugin.cmd) == "string" and { plugin.cmd } or plugin.cmd
    for _, cmd in ipairs(cmds) do
      vim.api.nvim_create_user_command(cmd, function(args)
        vim.api.nvim_del_user_command(cmd)
        load_once()
        pcall(vim.cmd, cmd .. " " .. (args.args or ""))
      end, { nargs = "*", desc = "garrys: lazy load " .. plugin.name })
    end
  end

  -- Lazy by filetype
  if plugin.ft then
    local fts = type(plugin.ft) == "string" and { plugin.ft } or plugin.ft
    vim.api.nvim_create_autocmd("FileType", { pattern = fts, once = true, callback = load_once })
  end

  -- Lazy by keymap
  if plugin.keys then
    local keys = type(plugin.keys) == "string" and { plugin.keys } or plugin.keys
    for _, key in ipairs(keys) do
      vim.keymap.set("n", key, function()
        vim.keymap.del("n", key)
        load_once()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "n", false)
      end, { desc = "garrys: lazy load " .. plugin.name })
    end
  end
end

function M.load_all(plugins)
  -- Enable bytecode cache
  vim.loader.enable()

  local sorted = u.sort_by_deps(plugins)

  for _, plugin in ipairs(sorted) do
    local is_lazy = plugin.lazy or plugin.event or plugin.cmd or plugin.ft or plugin.keys

    -- Track profile start
    local ok, prof = pcall(require, "garrys.profile")
    if ok then prof.start(plugin.name) end

    if is_lazy then
      -- Register lazy triggers
      -- If installed, also run init immediately (lazy.nvim compat)
      if plugin.init and u.is_installed(plugin.path) then
        pcall(plugin.init)
      end
      M.register(plugin)
    else
      M.inject(plugin)
    end
  end
end

return M
