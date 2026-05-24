local M = {}

-- Get git log between two commits or since N commits ago
local function git_log(path, since, callback)
  local args = {
    "git", "-C", path,
    "log", "--oneline", "--no-decorate",
    since and (since .. "..HEAD") or "-10",
  }
  vim.system(args, { text = true }, function(result)
    callback(result.code == 0, result.stdout, result.stderr)
  end)
end

-- Get commit before the last pull (ORIG_HEAD is set by git pull)
local function get_orig_head(path, callback)
  vim.system(
    { "git", "-C", path, "rev-parse", "ORIG_HEAD" },
    { text = true },
    function(result)
      local commit = result.stdout:gsub("%s+", "")
      callback(result.code == 0 and commit ~= "" and commit or nil)
    end
  )
end

function M.show(plugins)
  local ui    = require("garrys.ui")
  local u     = require("garrys.util")
  local total = vim.tbl_count(plugins)
  local done  = 0

  ui.open()
  ui.set_total(total)
  ui._footer = "diff since last update  —  q to close"

  for _, plugin in pairs(plugins) do
    if not u.is_installed(plugin.path) then
      done = done + 1
      ui.set_status(plugin.name, "✘ not installed")
      if done == total then
        ui._done = total
        ui.finish()
      end
    else
      get_orig_head(plugin.path, function(orig)
        if not orig then
          done = done + 1
          vim.schedule(function()
            ui.set_status(plugin.name, "· no update history")
            if done == total then ui.finish() end
          end)
          return
        end

        git_log(plugin.path, orig, function(ok, log_out)
          done = done + 1
          vim.schedule(function()
            if not ok or log_out:gsub("%s+", "") == "" then
              ui.set_status(plugin.name, "· up to date")
            else
              -- Show first commit message as the status
              local first = log_out:match("^([^\n]+)")
              local count = select(2, log_out:gsub("\n", "")) + 1
              local label = string.format("+%d  %s", count, first or "")
              ui.set_status(plugin.name, "✔ " .. label)
            end
            ui._done = done
            if done == total then ui.finish() end
          end)
        end)
      end)
    end
  end
end

return M
