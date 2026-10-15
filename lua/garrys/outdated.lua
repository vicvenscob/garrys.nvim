-- garrys.nvim — outdated.lua
-- :GarryOutdated — check which plugins have upstream commits waiting,
-- without pulling or touching the working tree (git fetch only).

local M   = {}
local git = require("garrys.git")
local u   = require("garrys.util")

function M.show(plugins)
  local ui    = require("garrys.ui")
  local total = vim.tbl_count(plugins)

  if total == 0 then
    u.info("no plugins to check")
    return
  end

  ui.open()
  ui.set_total(total)
  ui._footer = "outdated check  —  q to close"

  local done = 0

  for _, plugin in pairs(plugins) do
    if not u.is_installed(plugin.path) or not git.is_repo(plugin.path) then
      done = done + 1
      ui.set_status(plugin.name, "✘ not installed")
      if done == total then ui._done = total; ui.finish() end
    elseif plugin.pin then
      done = done + 1
      ui.set_status(plugin.name, "· pinned")
      if done == total then ui._done = total; ui.finish() end
    else
      ui.set_status(plugin.name, "fetching...")
      git.fetch(plugin.path, function(fetch_ok, fetch_err)
        if not fetch_ok then
          done = done + 1
          vim.schedule(function()
            ui.set_status(plugin.name, "✘ fetch failed: " .. (fetch_err or ""):gsub("\n", " "))
            ui._done = done
            if done == total then ui.finish() end
          end)
          return
        end

        git.behind_count(plugin.path, function(behind)
          done = done + 1
          vim.schedule(function()
            if behind == nil then
              ui.set_status(plugin.name, "· no upstream branch")
            elseif behind == 0 then
              ui.set_status(plugin.name, "· up to date")
            else
              ui.set_status(plugin.name, string.format("✔ %d commit%s behind", behind, behind == 1 and "" or "s"))
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
