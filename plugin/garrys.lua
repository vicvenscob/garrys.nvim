local function G()      return require("garrys")           end
local function git()    return require("garrys.git")        end
local function ui()     return require("garrys.ui")         end
local function u()      return require("garrys.util")       end
local function loader() return require("garrys.loader")     end

-- ── Install ────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryInstall", function(args)
  local garrys  = G()
  local pending = {}
  local source  = args.args ~= "" and args.args or nil

  if source then
    -- :GarryInstall user/repo — install a specific plugin
    local name   = source:match("[^/]+$")
    local plugin = garrys._plugins[name]

    if not plugin then
      -- Not in spec yet — add it temporarily
      plugin = garrys.add(source)
      if not plugin then
        u().err("invalid source: " .. source)
        return
      end
    end

    if u().is_installed(plugin.path) then
      u().info(plugin.name .. " is already installed")
      return
    end

    table.insert(pending, plugin)
  else
    -- :GarryInstall — install all missing
    for _, plugin in pairs(garrys._plugins) do
      if plugin._has_own_source ~= false
        and not plugin.offline
        and not u().is_installed(plugin.path) then
        table.insert(pending, plugin)
      end
    end
    table.sort(pending, function(a, b) return a.name < b.name end)
  end

  if #pending == 0 then
    u().info("everything is already installed")
    return
  end

  local _ui    = ui()
  local _git   = git()
  local done   = 0
  local active = 0
  local i      = 1

  _ui.open()
  _ui.set_total(#pending)

  local function clone_plugin(plugin, cb)
    local cmd = { "git", "clone", "--depth=1", "--filter=blob:none" }
    if plugin.git_ref then
      vim.list_extend(cmd, { "--branch", plugin.git_ref })
    end
    vim.list_extend(cmd, { plugin.url, plugin.path })
    vim.system(cmd, { text = true }, function(r) cb(r.code == 0, r.stderr) end)
  end

  local function dispatch()
    while active < garrys.config.concurrency and i <= #pending do
      local plugin = pending[i]; i = i + 1; active = active + 1
      _ui.set_status(plugin.name, "installing...")

      clone_plugin(plugin, function(ok, err)
        active = active - 1; done = done + 1
        vim.schedule(function()
          if ok then
            _ui.set_status(plugin.name, "✔ installed")
            pcall(loader().inject, plugin)
            if plugin.make then pcall(u().run_build, plugin) end
          else
            _ui.set_status(plugin.name, "⟳ retrying...")
            local retry = vim.tbl_extend("force", plugin, { git_ref = nil })
            clone_plugin(retry, function(rok, rerr)
              vim.schedule(function()
                if rok then
                  _ui.set_status(plugin.name, "✔ installed")
                  pcall(loader().inject, plugin)
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
end, { nargs = "?", desc = "Install missing plugins (or a specific one)" })

-- ── Update ─────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryUpdate", function(args)
  local garrys  = G()
  local plugins = {}
  local target  = args.args ~= "" and args.args or nil

  for _, p in pairs(garrys._plugins) do
    local name_match = not target or p.name == target or p.name == target:match("[^/]+$")
    if git().is_repo(p.path) and not p.pin and name_match then
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

      -- Capture commit before pull so we can show what changed
      _git.get_commit(plugin.path, function(before)
        _git.pull(plugin.path, function(ok, err)
          active = active - 1; done = done + 1
          vim.schedule(function()
            if ok then
              -- Show what changed (commit count)
              _git.get_commit(plugin.path, function(after)
                vim.schedule(function()
                  if before and after and before ~= after then
                    vim.system(
                      { "git", "-C", plugin.path, "log", "--oneline", before .. ".." .. after },
                      { text = true },
                      function(log)
                        vim.schedule(function()
                          local lines  = vim.split(log.stdout:gsub("%s+$", ""), "\n")
                          local count  = #vim.tbl_filter(function(l) return l ~= "" end, lines)
                          local msg    = count > 0 and ("✔ +" .. count .. " commit" .. (count == 1 and "" or "s")) or "✔ up to date"
                          _ui.set_status(plugin.name, msg)
                        end)
                      end
                    )
                  else
                    _ui.set_status(plugin.name, "✔ up to date")
                  end
                end)
              end)
            else
              _ui.set_status(plugin.name, "✘ " .. (err or "failed"):gsub("\n", " "))
            end
            if done == #plugins then _ui.finish() else dispatch() end
          end)
        end)
      end)
    end
  end

  dispatch()
end, { nargs = "?", desc = "Update all plugins (or a specific one)" })

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

  -- Also clean stale schedule entries
  local changed = false
  for name in pairs(garrys._schedule or {}) do
    if not garrys._plugins[name] then
      garrys._schedule[name] = nil
      changed = true
    end
  end
  if changed then garrys._save_schedule() end

  u().info(removed == 0 and "nothing to clean" or "cleaned " .. removed .. " plugin(s)")
end, { desc = "Remove unlisted plugins" })

-- ── Lock / Restore ─────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryLock", function()
  require("garrys.lockfile").write(G()._plugins)
end, { desc = "Write garrys.lock" })

vim.api.nvim_create_user_command("GarryRestore", function()
  local garrys  = G()
  local lock    = require("garrys.lockfile").read()
  local _git    = git()

  if vim.tbl_count(lock) == 0 then
    u().warn("no lockfile found — run :GarryLock first")
    return
  end

  local _ui = ui()
  local total = vim.tbl_count(garrys._plugins)
  local done  = 0

  _ui.open()
  _ui.set_total(total)

  for _, plugin in pairs(garrys._plugins) do
    local entry = lock[plugin.name]

    if not entry then
      done = done + 1
      _ui.set_status(plugin.name, "· not in lockfile")
      if done == total then _ui.finish() end
    elseif plugin.branch or plugin.tag then
      -- For branch/tag pins, just pull to make sure we're on the right ref
      _git.pull(plugin.path, function(ok, err)
        done = done + 1
        vim.schedule(function()
          _ui.set_status(plugin.name, ok and "✔ restored" or "✘ " .. (err or ""):gsub("\n", " "))
          if done == total then _ui.finish() end
        end)
      end)
    else
      -- Checkout exact commit from lockfile
      _git.checkout(plugin.path, entry.commit, function(ok, err)
        done = done + 1
        vim.schedule(function()
          _ui.set_status(plugin.name, ok
            and "✔ " .. entry.commit:sub(1, 7)
            or  "✘ " .. (err or ""):gsub("\n", " "))
          if done == total then _ui.finish() end
        end)
      end)
    end
  end
end, { desc = "Restore plugins to locked commits" })

-- ── Status ─────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryStatus", function()
  ui().open_status(G()._plugins)
end, { desc = "Show plugin status" })

vim.api.nvim_create_user_command("GarryList", function()
  local plugins = {}
  for name, plugin in pairs(G()._plugins) do
    table.insert(plugins, plugin)
  end
  table.sort(plugins, function(a, b) return a.name < b.name end)

  local installed_ct = 0
  local missing_ct   = 0

  for _, plugin in ipairs(plugins) do
    local installed = u().is_installed(plugin.path)
    local status    = installed and "✔" or "✘"
    local flags     = {}
    if plugin._loaded  then table.insert(flags, "loaded")   end
    if plugin.lazy or plugin.event or plugin.cmd or plugin.ft
                       then table.insert(flags, "lazy")    end
    if plugin.pin      then table.insert(flags, "pinned")   end
    if plugin.group    then table.insert(flags, plugin.group) end
    if plugin.offline  then table.insert(flags, "offline")  end
    if plugin.update   then table.insert(flags, plugin.update) end

    local flag_str = #flags > 0 and "  [" .. table.concat(flags, ", ") .. "]" or ""
    print(status .. "  " .. plugin.name .. flag_str)

    if installed then installed_ct = installed_ct + 1
    else              missing_ct   = missing_ct   + 1 end
  end

  print("")
  print(installed_ct .. " installed  ·  " .. missing_ct .. " missing  ·  " .. #plugins .. " total")
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
      if not _git.is_repo(plugin.path) then table.insert(issues, "broken repo") end
      local has_lua    = u().is_installed(plugin.path .. "/lua")
      local has_plugin = u().is_installed(plugin.path .. "/plugin")
      local has_after  = u().is_installed(plugin.path .. "/after")
      if not has_lua and not has_plugin and not has_after then
        table.insert(issues, "no loadable dirs")
      end
      if has_lua then
        local candidates = {
          plugin.name,
          plugin.name:gsub("%.nvim$", ""),
          plugin.name:gsub("%-nvim$", ""),
          plugin.name:gsub("nvim%-", ""),
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

-- ── Add ────────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryAdd", function(args)
  local source = args.args
  if source == "" then u().warn("usage: :GarryAdd user/repo"); return end

  local garrys = G()
  local plugin = garrys.add(source)
  if not plugin then u().err("invalid source: " .. source); return end

  if u().is_installed(plugin.path) then
    u().info(plugin.name .. " already installed — loading...")
    pcall(loader().inject, plugin)
    return
  end

  local _ui = ui()
  _ui.open()
  _ui.set_total(1)
  _ui.set_status(plugin.name, "installing...")

  git().clone(plugin.url, plugin.path, function(ok, err)
    vim.schedule(function()
      if ok then
        _ui.set_status(plugin.name, "✔ installed")
        pcall(loader().inject, plugin)
        _ui.finish()
        u().info("add to your config to keep it:\n  { \"" .. source .. "\" }")
      else
        _ui.set_status(plugin.name, "✘ " .. (err or "failed"):gsub("\n", " "))
        _ui.finish()
      end
    end)
  end)
end, { nargs = 1, desc = "Install a plugin live" })

-- ── Groups ─────────────────────────────────────────────────────────────────
vim.api.nvim_create_user_command("GarryGroup", function(args)
  local parts  = vim.split(args.args, " ")
  local name   = parts[1]
  local action = parts[2]

  if not name or name == "" then
    local groups = G().group_list()
    if #groups == 0 then u().info("no groups defined"); return end
    for _, g in ipairs(groups) do
      local status = g.enabled and "✔" or "✘"
      print(status .. "  " .. g.name .. "  (" .. g.count .. " plugins)")
    end
    return
  end

  if     action == "on"  then G().group_enable(name)
  elseif action == "off" then G().group_disable(name)
  else u().warn("usage: :GarryGroup [name] [on|off]") end
end, { nargs = "*", desc = "Enable/disable plugin groups" })

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

  local out_path = require("garrys.migrate").convert(input)
  if not out_path then return end

  vim.schedule(function()
    u().info(
      "migrated → " .. out_path .. "\n"
      .. "  1. review the output file\n"
      .. "  2. swap your lazy bootstrapper for garrys\n"
      .. "  3. open Neovim — plugins install automatically"
    )
  end)
end, { nargs = "?", complete = "file", desc = "Migrate lazy.nvim spec" })

vim.api.nvim_create_user_command("GarryValidate", function()
  require("garrys.migrate").validate()
end, { desc = "Validate plugin dependency declarations" })
