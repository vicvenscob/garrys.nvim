local M    = {}
local path = vim.fn.stdpath("data") .. "/garrys/profile.json"

M._times = {}

function M.start(name)
  M._times[name] = { start = vim.loop.hrtime() }
end

function M.stop(name)
  local entry = M._times[name]
  if not entry or entry.ms then return end
  entry.stop = vim.loop.hrtime()
  entry.ms   = (entry.stop - entry.start) / 1e6
end

function M.get(name)
  local e = M._times[name]
  return e and e.ms or 0
end

-- Save profile to disk so it persists between sessions
function M.save()
  local data = {}
  for name, entry in pairs(M._times) do
    if entry.ms then data[name] = entry.ms end
  end
  local f = io.open(path, "w")
  if not f then return end
  f:write(vim.json.encode(data))
  f:close()
end

-- Load last session's profile data
function M.load()
  local f = io.open(path, "r")
  if not f then return end
  local raw = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, raw)
  if ok and data then
    for name, ms in pairs(data) do
      M._times[name] = M._times[name] or {}
      -- Only use persisted data if we don't have live data
      if not M._times[name].ms then
        M._times[name].ms = ms
      end
    end
  end
end

function M.report()
  -- Load persisted data first
  M.load()

  local results = {}
  for name, entry in pairs(M._times) do
    if entry.ms then
      table.insert(results, { name = name, ms = entry.ms })
    end
  end

  if #results == 0 then
    require("garrys.util").info("no profile data yet — restart Neovim to collect timing")
    return
  end

  table.sort(results, function(a, b) return a.ms > b.ms end)

  local _ui   = require("garrys.ui")
  local total = 0
  for _, r in ipairs(results) do total = total + r.ms end

  _ui.open()
  _ui.set_total(#results)

  local max_ms = results[1].ms
  for _, r in ipairs(results) do
    local bar_w  = 24
    local filled = math.floor((r.ms / max_ms) * bar_w)
    local bar    = string.rep("█", filled) .. string.rep("░", bar_w - filled)
    _ui.set_status(r.name, bar .. string.format("  %.1fms", r.ms))
    _ui._done = (_ui._done or 0) + 1
  end

  _ui._footer  = string.format("total: %.1fms  —  q close", total)
  _ui._elapsed = total / 1000
  _ui.finish()
end

-- Save on exit
vim.api.nvim_create_autocmd("VimLeave", {
  callback = function() M.save() end,
})

return M
