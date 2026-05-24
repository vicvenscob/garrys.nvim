local M   = {}
local git = require("garrys.git")
local u   = require("garrys.util")

function M.write(plugins)
  local lock  = {}
  local count = 0
  local total = vim.tbl_count(plugins)

  if total == 0 then
    u.warn("no plugins to lock")
    return
  end

  for _, plugin in pairs(plugins) do
    if git.is_repo(plugin.path) then
      git.get_commit(plugin.path, function(commit)
        count = count + 1
        lock[plugin.name] = {
          commit = commit,
          url    = plugin.url,
        }

        if count == total then
          vim.schedule(function()
            local path = require("garrys").config.lockfile
            local f    = io.open(path, "w")
            if not f then
              u.err("could not write lockfile to " .. path)
              return
            end
            f:write(vim.json.encode(lock))
            f:close()
            u.info("lockfile written → " .. path)
          end)
        end
      end)
    else
      total = total - 1
    end
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
