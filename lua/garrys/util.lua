local M = {}

-- Logging levels
local levels = {
  debug = vim.log.levels.DEBUG,
  info  = vim.log.levels.INFO,
  warn  = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

function M.log(msg, level)
  vim.notify("[garrys] " .. msg, levels[level] or levels.info)
end

function M.debug(msg) M.log(msg, "debug") end
function M.info(msg)  M.log(msg, "info")  end
function M.warn(msg)  M.log(msg, "warn")  end
function M.err(msg)   M.log(msg, "error") end

-- Check if a plugin is installed on disk
function M.is_installed(path)
  return vim.loop.fs_stat(path) ~= nil
end

-- Consistent plugin install path
function M.plugin_path(base, name)
  return base .. "/" .. name
end

-- Scan a directory and return all subdirectory names
function M.list_installed(base)
  local result = {}
  local handle = vim.loop.fs_scandir(base)
  if not handle then return result end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then break end
    if type == "directory" then
      table.insert(result, name)
    end
  end

  return result
end

-- Shallow copy a table
function M.copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- Merge tables (right wins)
function M.merge(...)
  return vim.tbl_deep_extend("force", ...)
end

-- Run a build hook after install
function M.run_build(plugin)
  if not plugin.build then return end

  if type(plugin.build) == "string" then
    local ok, err = pcall(vim.cmd, plugin.build)
    if not ok then
      M.err("build failed for " .. plugin.name .. ": " .. err)
    end
  elseif type(plugin.build) == "function" then
    local ok, err = pcall(plugin.build)
    if not ok then
      M.err("build failed for " .. plugin.name .. ": " .. err)
    end
  end
end

-- Sort plugins respecting dependencies
-- Returns a list of plugins in load order
function M.sort_by_deps(plugins)
  local sorted  = {}
  local visited = {}

  local function visit(name)
    if visited[name] then return end
    visited[name] = true

    local plugin = plugins[name]
    if not plugin then return end

    -- Visit dependencies first
    for _, dep in ipairs(plugin.dep or {}) do
      local dep_name = dep:match("[^/]+$")
      visit(dep_name)
    end

    table.insert(sorted, plugin)
  end

  for name in pairs(plugins) do
    visit(name)
  end

  return sorted
end

return M
