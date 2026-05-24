local function G() return require("garrys") end
local function git() return require("garrys.git") end
local function ui()  return require("garrys.ui") end
local function u()   return require("garrys.util") end

-- ── Install ────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryInstall", function()
  local garrys  = G()
  local pending = {}

  for _, plugin in pairs(garrys._plugins) do
    if not u().is_installed(plugin.path) then
      table.insert(pending, plugin)
    end
  end

  if #pending == 0 then
    u().info("everything is already installed")
    return
  end

  -- Sort by name for consistent ordering
  table.sort(pending, function(a, b) return a.name < b.name end)

  local _ui     = ui()
  local _git    = git()
  local loader  = require("garrys.loader")
  local done    = 0
  local active  = 0
  local i       = 1

  _ui.open()
  _ui.set_total(#pending)

  local function dispatch()
    while active < garrys.config.concurrency and i <= #pending do
      local plugin = pending[i]; i = i + 1; active = active + 1
      _ui.set_status(plugin.name, "installing...")

      _git.clone(plugin.url, plugin.path, function(ok, err)
        active = active - 1
        done   = done + 1
        vim.schedule(function()
          if ok then
            _ui.set_status(plugin.name, "✔ installed")
            pcall(loader.inject, plugin)
            if plugin.make then pcall(u().run_build, plugin) end
          else
            -- Retry once
            _git.clone(plugin.url, plugin.path, function(rok, rerr)
              vim.schedule(function()
                if rok then
                  _ui.set_status(plugin.name, "✔ installed")
                  pcall(loader.inject, plugin)
                else
                  _ui.set_status(plugin.name, "✘ " .. (rerr or err or "failed"):gsub("\n", " "))
                end
              end)
            end)
          end
          if done == #pending then _ui.finish() else dispatch() end
        end)
      end)
    end
  end

  dispatch()
end, { desc = "Install missing plugins" })

-- ── Update ─────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryUpdate", function()
  local garrys  = G()
  local plugins = {}

  for _, p in pairs(garrys._plugins) do
    if git().is_repo(p.path) and not p.pin then
      table.insert(plugins, p)
    end
  end

  table.sort(plugins, function(a, b) return a.name < b.name end)

  if #plugins == 0 then u().info("nothing to update"); return end

  local _ui    = ui()
  local _git   = git()
  local done   = 0
  local active = 0
  local i      = 1

  _ui.open()
  _ui.set_total(#plugins)

  local function dispatch()
    while active < garrys.config.concurrency and i <= #plugins do
      local plugin = plugins[i]; i = i + 1; active = active + 1
      _ui.set_status(plugin.name, "updating...")

      _git.pull(plugin.path, function(ok, err)
        active = active - 1; done = done + 1
        vim.schedule(function()
          if ok then _ui.set_status(plugin.name, "✔ updated")
          else       _ui.set_status(plugin.name, "✘ " .. (err or "failed"):gsub("\n", " ")) end
          if done == #plugins then _ui.finish() else dispatch() end
        end)
      end)
    end
  end

  dispatch()
end, { desc = "Update all plugins" })

-- ── Clean ──────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryClean", function()
  local garrys    = G()
  local installed = u().list_installed(garrys.config.path)
  local removed   = 0

  for _, name in ipairs(installed) do
    if not garrys._plugins[name] then
      vim.fn.delete(garrys.config.path .. "/" .. name, "rf")
      u().info("removed " .. name)
      removed = removed + 1
    end
  end

  u().info(removed == 0 and "nothing to clean" or "cleaned " .. removed .. " plugin(s)")
end, { desc = "Remove unlisted plugins" })

-- ── Lock / Restore ─────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryLock", function()
  require("garrys.lockfile").write(G()._plugins)
end, { desc = "Write garrys.lock" })

vim.api.nvim_create_user_command("GarryRestore", function()
  require("garrys.lockfile").restore(G()._plugins)
end, { desc = "Restore plugins to locked commits" })

-- ── Status ─────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryStatus", function()
  ui().open_status(G()._plugins)
end, { desc = "Show plugin status" })

vim.api.nvim_create_user_command("GarryList", function()
  for name, plugin in pairs(G()._plugins) do
    local status  = u().is_installed(plugin.path) and "✔" or "✘"
    local loaded  = plugin._loaded and "[loaded]" or "[not loaded]"
    local lazy    = (plugin.lazy or plugin.event or plugin.cmd or plugin.ft) and "[lazy]" or ""
    print(status .. " " .. name .. " " .. loaded .. " " .. lazy)
  end
end, { desc = "List all plugins" })

-- ── Health ─────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryHealth", function()
  local garrys = G()
  local total  = vim.tbl_count(garrys._plugins)
  if total == 0 then u().warn("no plugins registered"); return end

  local _ui   = ui()
  local _git  = git()
  local count = 0

  _ui.open()
  _ui.set_total(total)

  for _, plugin in pairs(garrys._plugins) do
    local issues = {}

    if not u().is_installed(plugin.path) then
      table.insert(issues, "not installed")
    else
      if not _git.is_repo(plugin.path) then table.insert(issues, "broken git repo") end
      local has_lua    = u().is_installed(plugin.path .. "/lua")
      local has_plugin = u().is_installed(plugin.path .. "/plugin")
      local has_after  = u().is_installed(plugin.path .. "/after")
      if not has_lua and not has_plugin and not has_after then
        table.insert(issues, "no loadable dirs")
      end
      if has_lua then
        -- Try multiple module name patterns
        local candidates = {
          plugin.name,
          plugin.name:gsub("%.nvim$", ""),
          plugin.name:gsub("%-nvim$", ""),
        }
        local can_load = false
        for _, mod in ipairs(candidates) do
          if pcall(require, mod) then can_load = true; break end
        end
        if not can_load then table.insert(issues, "require() failed") end
      end
    end

    count = count + 1
    vim.schedule(function()
      if #issues == 0 then _ui.set_status(plugin.name, "✔ healthy")
      else               _ui.set_status(plugin.name, "✘ " .. table.concat(issues, ", ")) end
      if count == total then _ui.finish() end
    end)
  end
end, { desc = "Check plugin health" })

-- ── Profile ────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryProfile", function()
  require("garrys.profile").report()
end, { desc = "Show startup time per plugin" })

-- ── Diff ───────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryDiff", function()
  require("garrys.diff").show(G()._plugins)
end, { desc = "Show what changed since last update" })

-- ── Search ─────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarrySearch", function(args)
  require("garrys.search").pick(args.args)
end, { nargs = "+", desc = "Search GitHub for plugins" })

-- ── Migrate ────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryMigrate", function(args)
  local input = args.args ~= "" and args.args or nil

  if not input then
    local candidates = {
      vim.fn.stdpath("config") .. "/lua/plugins/init.lua",
      vim.fn.stdpath("config") .. "/lua/plugins.lua",
      vim.fn.stdpath("config") .. "/init.lua",
    }
    for _, path in ipairs(candidates) do
      if vim.loop.fs_stat(path) then input = path; break end
    end
  end

  if not input then
    u().err("no file found — usage: :GarryMigrate path/to/lazy/spec.lua")
    return
  end

  local migrate  = require("garrys.migrate")
  local out_path = migrate.convert(input)
  if not out_path then return end

  vim.schedule(function()
    u().info(
      "next steps:\n"
      .. "  1. review " .. out_path .. "\n"
      .. "  2. replace your lazy spec with the garrys equivalent\n"
      .. "  3. open Neovim — missing plugins install automatically"
    )
  end)
end, { nargs = "?", complete = "file", desc = "Migrate lazy.nvim spec" })

vim.api.nvim_create_user_command("GarryValidate", function()
  require("garrys.migrate").validate()
end, { desc = "Validate plugin dependency declarations" })

-- ── Add (install a plugin live from cmdline) ───────────────────────────────
vim.api.nvim_create_user_command("GarryAdd", function(args)
  local source = args.args
  if source == "" then
    u().warn("usage: :GarryAdd user/repo")
    return
  end

  local garrys = G()
  local plugin = garrys.add(source)
  if not plugin then
    u().err("invalid plugin source: " .. source)
    return
  end

  if u().is_installed(plugin.path) then
    u().info(plugin.name .. " is already installed")
    return
  end

  local _ui    = ui()
  local loader = require("garrys.loader")

  _ui.open()
  _ui.set_total(1)
  _ui.set_status(plugin.name, "installing...")

  git().clone(plugin.url, plugin.path, function(ok, err)
    vim.schedule(function()
      if ok then
        _ui.set_status(plugin.name, "✔ installed")
        pcall(loader.inject, plugin)
        _ui.finish()
        u().info("add this to your config to keep it:\n  { \"" .. source .. "\" }")
      else
        _ui.set_status(plugin.name, "✘ " .. (err or "failed"):gsub("\n", " "))
        _ui.finish()
      end
    end)
  end)
end, { nargs = 1, desc = "Install a plugin live from cmdline" })

-- ── Groups ─────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryGroup", function(args)
  local parts  = vim.split(args.args, " ")
  local name   = parts[1]
  local action = parts[2]

  if not name or name == "" then
    -- List all groups
    local groups = G().group_list()
    if #groups == 0 then
      u().info("no groups defined")
      return
    end
    for _, g in ipairs(groups) do
      local status = g.enabled and "✔" or "✘"
      print(status .. " " .. g.name .. " (" .. g.count .. " plugins)")
    end
    return
  end

  if action == "on"  then G().group_enable(name)
  elseif action == "off" then G().group_disable(name)
  else
    u().warn("usage: :GarryGroup [name] [on|off]")
  end
end, { nargs = "*", desc = "Enable/disable plugin groups" })
