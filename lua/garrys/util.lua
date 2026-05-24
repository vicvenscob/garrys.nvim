local M = {}

-- Batched notification queue — flushes after startup to avoid spam
local _queue   = {}
local _flushed = false

local function flush_queue()
  if #_queue == 0 then return end
  if #_queue == 1 then
    vim.notify(_queue[1].msg, _queue[1].level)
  else
    -- Batch into single notification grouped by level
    local errors = {}
    local warns  = {}
    local infos  = {}
    for _, item in ipairs(_queue) do
      if     item.level == vim.log.levels.ERROR then table.insert(errors, item.msg)
      elseif item.level == vim.log.levels.WARN  then table.insert(warns,  item.msg)
      else                                           table.insert(infos,  item.msg)
      end
    end
    if #errors > 0 then vim.notify(table.concat(errors, "\n"), vim.log.levels.ERROR) end
    if #warns  > 0 then vim.notify(table.concat(warns,  "\n"), vim.log.levels.WARN)  end
    if #infos  > 0 then vim.notify(table.concat(infos,  "\n"), vim.log.levels.INFO)  end
  end
  _queue   = {}
  _flushed = true
end

vim.api.nvim_create_autocmd("VimEnter", {
  once     = true,
  callback = vim.schedule_wrap(flush_queue),
})

local function notify(msg, level)
  msg = "[garrys] " .. msg
  if _flushed then
    vim.notify(msg, level)
  else
    table.insert(_queue, { msg = msg, level = level })
  end
end

function M.log(msg, level) notify(msg, level or vim.log.levels.INFO) end
function M.debug(msg) notify(msg, vim.log.levels.DEBUG) end
function M.info(msg)  notify(msg, vim.log.levels.INFO)  end
function M.warn(msg)  notify(msg, vim.log.levels.WARN)  end
function M.err(msg)   notify(msg, vim.log.levels.ERROR) end

function M.is_installed(path)
  return vim.loop.fs_stat(path) ~= nil
end

function M.plugin_path(base, name)
  return base .. "/" .. name
end

function M.list_installed(base)
  local result = {}
  local handle = vim.loop.fs_scandir(base)
  if not handle then return result end
  while true do
    local name, ftype = vim.loop.fs_scandir_next(handle)
    if not name then break end
    if ftype == "directory" then table.insert(result, name) end
  end
  return result
end

function M.copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function M.merge(...)
  return vim.tbl_deep_extend("force", ...)
end

function M.run_build(plugin)
  if not plugin.make then return end
  if type(plugin.make) == "string" then
    local ok, err = pcall(vim.cmd, plugin.make)
    if not ok then M.err("build failed for " .. plugin.name .. ": " .. err) end
  elseif type(plugin.make) == "function" then
    local ok, err = pcall(plugin.make)
    if not ok then M.err("build failed for " .. plugin.name .. ": " .. err) end
  end
end

function M.sort_by_deps(plugins)
  local sorted  = {}
  local visited = {}

  local function visit(name)
    if visited[name] then return end
    visited[name] = true
    local plugin  = plugins[name]
    if not plugin then return end
    for _, dep in ipairs(plugin.dep or {}) do
      visit(dep:match("[^/]+$"))
    end
    table.insert(sorted, plugin)
  end

  for name in pairs(plugins) do visit(name) end
  return sorted
end

return M
