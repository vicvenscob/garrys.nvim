-- garrys.nvim — plugin/garrys.lua
-- User commands. Auto-sourced from rtp by the bootstrap snippet.
--
-- NOTE: this file was not among the files you uploaded, so it's written
-- fresh here against the module APIs in lua/garrys/*.lua (README-documented
-- commands + the four new ones added below). If you have your own original
-- plugin/garrys.lua, diff it against this one rather than overwriting blind.

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

local function garrys() return require("garrys") end

-- ── Install / Update ─────────────────────────────────────────────────────

cmd("GarryInstall", function(args)
  local g   = garrys()
  local git = require("garrys.git")
  local u   = require("garrys.util")
  local ui  = require("garrys.ui")

  local targets = {}
  if args.args ~= "" then
    local plugin = g._plugins[args.args:match("[^/]+$")]
    if not plugin then u.err("unknown plugin: " .. args.args); return end
    table.insert(targets, plugin)
  else
    for _, p in pairs(g._plugins) do
      if p._has_own_source ~= false and not u.is_installed(p.path) then
        table.insert(targets, p)
      end
    end
  end

  if #targets == 0 then u.info("nothing to install"); return end

  ui.open(); ui.set_total(#targets)
  for _, plugin in ipairs(targets) do
    ui.set_status(plugin.name, "installing...")
    git.clone(plugin.url, plugin.path, function(ok, err)
      vim.schedule(function()
        if ok then
          ui.set_status(plugin.name, "✔ installed")
          pcall(require("garrys.loader").inject, plugin)
          if plugin.make then pcall(u.run_build, plugin) end
        else
          ui.set_status(plugin.name, "✘ " .. (err or "failed"):gsub("\n", " "))
        end
      end)
    end)
  end
end, { nargs = "?", desc = "Install missing plugin(s)" })

cmd("GarryUpdate", function(args)
  local g   = garrys()
  local git = require("garrys.git")
  local u   = require("garrys.util")
  local ui  = require("garrys.ui")

  local targets = {}
  if args.args ~= "" then
    local plugin = g._plugins[args.args:match("[^/]+$")]
    if not plugin then u.err("unknown plugin: " .. args.args); return end
    table.insert(targets, plugin)
  else
    for _, p in pairs(g._plugins) do
      if not p.pin and u.is_installed(p.path) then
        table.insert(targets, p)
      end
    end
  end

  if #targets == 0 then u.info("nothing to update"); return end

  ui.open(); ui.set_total(#targets)
  for _, plugin in ipairs(targets) do
    ui.set_status(plugin.name, "updating...")
    git.pull(plugin.path, function(ok, err)
      vim.schedule(function()
        ui.set_status(plugin.name, ok and "✔ updated" or ("✘ " .. (err or ""):gsub("\n", " ")))
      end)
    end)
  end
end, { nargs = "?", desc = "Update plugin(s)" })

cmd("GarryAdd", function(args)
  if args.args == "" then require("garrys.util").warn("usage: :GarryAdd user/repo"); return end
  garrys().add(args.args)
  vim.cmd("GarryInstall " .. args.args)
end, { nargs = 1, desc = "Install a plugin live, outside your config" })

-- ── Clean ─────────────────────────────────────────────────────────────────

cmd("GarryClean", function(args)
  garrys().clean({ force = args.bang })
end, { bang = true, desc = "Remove installed plugins not in your spec (! to skip confirmation)" })

-- ── Status / Health / Profile / Diff / Outdated ──────────────────────────

cmd("GarryStatus", function()
  require("garrys.ui").open_status(garrys()._active_plugins())
end, { desc = "Open the tabbed HUD" })

cmd("GarryHealth", function()
  local u   = require("garrys.util")
  local ok_n, fail_n = 0, 0
  for name, plugin in pairs(garrys()._plugins) do
    if plugin._has_own_source == false then goto continue end
    if not u.is_installed(plugin.path) then
      u.err(name .. ": not installed")
      fail_n = fail_n + 1
      goto continue
    end
    if not require("garrys.git").is_repo(plugin.path) then
      u.warn(name .. ": installed but not a git repo")
    end
    ok_n = ok_n + 1
    ::continue::
  end
  u.info(string.format("health: %d ok, %d failed", ok_n, fail_n))
end, { desc = "Validate every plugin on disk" })

cmd("GarryProfile", function()
  require("garrys.profile").report()
end, { desc = "Rank plugins by startup load time" })

cmd("GarryDiff", function()
  require("garrys.diff").show(garrys()._active_plugins())
end, { desc = "Show what changed per plugin since last update" })

cmd("GarryOutdated", function()
  require("garrys.outdated").show(garrys()._active_plugins())
end, { desc = "Check for upstream updates without pulling" })

-- ── Lockfile ──────────────────────────────────────────────────────────────

cmd("GarryLock", function()
  require("garrys.lockfile").write(garrys()._active_plugins())
end, { desc = "Pin every plugin to its current commit" })

cmd("GarryRestore", function()
  require("garrys.lockfile").restore(garrys()._active_plugins())
end, { desc = "Roll back every plugin to its locked commit" })

-- ── Groups ────────────────────────────────────────────────────────────────

cmd("GarryGroup", function(args)
  local g       = garrys()
  local parts   = vim.split(args.args, "%s+", { trimempty = true })
  if #parts == 0 then
    for _, grp in ipairs(g.group_list()) do
      vim.notify(string.format("[garrys] %-20s %s  (%d plugins)", grp.name, grp.enabled and "on" or "off", grp.count))
    end
    return
  end
  local name, action = parts[1], parts[2]
  if action == "off" then g.group_disable(name)
  elseif action == "on" then g.group_enable(name)
  else require("garrys.util").warn("usage: :GarryGroup <name> on|off") end
end, { nargs = "*", desc = "List or toggle plugin groups" })

-- ── Search / Migrate / Validate / List ───────────────────────────────────

cmd("GarrySearch", function(args)
  require("garrys.search").pick(args.args)
end, { nargs = "*", desc = "Search GitHub and install live" })

cmd("GarryMigrate", function(args)
  local path = args.args ~= "" and args.args or (vim.fn.stdpath("config") .. "/lua/plugins/init.lua")
  require("garrys.migrate").convert(path)
end, { nargs = "?", complete = "file", desc = "Convert a lazy.nvim spec file" })

cmd("GarryValidate", function()
  require("garrys.migrate").validate()
end, { desc = "Check all declared deps are in your spec" })

cmd("GarryList", function()
  local u = require("garrys.util")
  local names = {}
  for name in pairs(garrys()._plugins) do table.insert(names, name) end
  table.sort(names)
  for _, name in ipairs(names) do
    local p     = garrys()._plugins[name]
    local flags = {}
    if u.is_installed(p.path) then table.insert(flags, "installed") end
    if p.lazy or p.event or p.cmd or p.ft or p.keys then table.insert(flags, "lazy") end
    if p.pin then table.insert(flags, "pinned") end
    if p.group then table.insert(flags, "group:" .. p.group) end
    if p.offline then table.insert(flags, "offline") end
    vim.notify(string.format("[garrys] %-30s %s", name, table.concat(flags, " ")))
  end
end, { desc = "Sorted list of plugins with flags" })

-- ── New: Info / Pin / Unpin ───────────────────────────────────────────────

cmd("GarryInfo", function(args)
  if args.args == "" then require("garrys.util").warn("usage: :GarryInfo <name>"); return end
  garrys().info(args.args)
end, {
  nargs = 1,
  complete = function()
    local names = {}
    for name in pairs(garrys()._plugins) do table.insert(names, name) end
    return names
  end,
  desc = "Show everything garrys.nvim knows about one plugin",
})

cmd("GarryPin", function(args)
  if args.args == "" then require("garrys.util").warn("usage: :GarryPin <name>"); return end
  garrys().pin(args.args)
end, { nargs = 1, desc = "Pin a plugin so :GarryUpdate skips it" })

cmd("GarryUnpin", function(args)
  if args.args == "" then require("garrys.util").warn("usage: :GarryUnpin <name>"); return end
  garrys().unpin(args.args)
end, { nargs = 1, desc = "Unpin a plugin" })
