local M = {}

M._times = {}  -- name -> { start, stop, ms }

function M.start(name)
  M._times[name] = { start = vim.loop.hrtime() }
end

function M.stop(name)
  local entry = M._times[name]
  if not entry then return end
  entry.stop = vim.loop.hrtime()
  entry.ms   = (entry.stop - entry.start) / 1e6
end

function M.get(name)
  local e = M._times[name]
  return e and e.ms or 0
end

function M.report()
  local u       = require("garrys.util")
  local results = {}

  for name, entry in pairs(M._times) do
    if entry.ms then
      table.insert(results, { name = name, ms = entry.ms })
    end
  end

  if #results == 0 then
    u.info("no profile data — plugins may already be loaded")
    return
  end

  -- Sort slowest first
  table.sort(results, function(a, b) return a.ms > b.ms end)

  local ui  = require("garrys.ui")
  local total = 0

  ui.open()
  ui.set_total(#results)
  ui._footer = "startup profile  —  q to close"

  for _, r in ipairs(results) do
    total = total + r.ms
    local bar_width = 20
    local max_ms    = results[1].ms  -- slowest is 100%
    local filled    = math.floor((r.ms / max_ms) * bar_width)
    local bar       = string.rep("█", filled) .. string.rep("░", bar_width - filled)
    local label     = string.format("%s  %.2fms", bar, r.ms)
    ui.set_status(r.name, label)
  end

  ui._done  = #results
  ui._total = #results
  ui._footer = string.format("total: %.2fms  —  q to close", total)
  ui.finish()
end

return M
