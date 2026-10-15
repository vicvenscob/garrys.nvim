local M   = {}
local git = require("garrys.git")
local u   = require("garrys.util")

local function flush(lock, written_count)
  local path = require("garrys").config.lockfile
  local f    = io.open(path, "w")
  if not f then
    u.err("could not write lockfile to " .. path)
    return
  end
  f:write(vim.json.encode(lock))
  f:close()
  u.info("lockfile written → " .. path .. " (" .. written_count .. " plugin(s))")
end

function M.write(plugins)
  local lock  = {}
  local count = 0

  -- Only plugins backed by an actual git repo on disk can be locked.
  local repo_plugins = {}
  for _, plugin in pairs(plugins) do
    if git.is_repo(plugin.path) then
      table.insert(repo_plugins, plugin)
    end
  end

  local total = #repo_plugins
  if total == 0 then
    u.warn("no plugins to lock (none are installed git repos)")
    return
  end

  for _, plugin in ipairs(repo_plugins) do
    git.get_commit(plugin.path, function(commit)
      count = count + 1
      lock[plugin.name] = {
        commit = commit,
        url    = plugin.url,
      }
      if count == total then
        vim.schedule(function() flush(lock, total) end)
      end
    end)
  end
end

function M.read()
  local path = require("garrys").config.lockfile
  local f    = io.open(path, "r")
  if not f then return {} end
  local raw = f:read("*a")
  f:close()

  local ok, data = pcall(vim.json.decode, raw)
  if not ok then
    require("garrys.util").err("garrys.lock is corrupted")
    return {}
  end

  return data
end

-- Restore every plugin to its locked commit
function M.restore(plugins)
  local lock = M.read()

  if vim.tbl_count(lock) == 0 then
    u.warn("no lockfile found — run :GarryLock first")
    return
  end

  for _, plugin in pairs(plugins) do
    local entry = lock[plugin.name]
    if entry and entry.commit then
      git.checkout(plugin.path, entry.commit, function(ok, err)
        vim.schedule(function()
          if ok then
            u.info("✓ " .. plugin.name .. " → " .. entry.commit:sub(1, 7))
          else
            u.err("✗ " .. plugin.name .. ": " .. (err or "checkout failed"))
          end
        end)
      end)
    else
      u.warn(plugin.name .. " not in lockfile, skipping")
    end
  end
end

return M
