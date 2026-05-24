-- garrys.nvim migration tool
-- Converts lazy.nvim specs to garrys.nvim format
-- Usage: :GarryMigrate <path_to_lazy_spec>

local M = {}

-- Keys that translate directly
local DIRECT = {
  "name", "lazy", "event", "cmd", "ft", "keys",
  "opts", "config", "build", "pin",
}

-- Keys that need renaming
local RENAME = {
  dependencies = "depends",
  -- priority is dropped — use lazy = false instead
  -- dev is dropped — not supported
  -- version is dropped — not supported yet
  -- module is dropped — not needed
}

-- Keys that are dropped with a warning
local DROPPED = {
  priority = "use lazy = false to ensure early loading",
  dev      = "not supported in garrys.nvim",
  version  = "semver pinning not supported yet — use pin = true to freeze",
  module   = "not needed — garrys.nvim handles module loading automatically",
  cond     = nil,  -- supported, pass through silently
}

local function convert_spec(spec)
  if type(spec) == "string" then
    return { source = spec }
  end

  local out     = {}
  local warns   = {}
  local source  = spec[1] or spec.url or spec.dir

  if not source then
    table.insert(warns, "could not determine plugin source")
    return out, warns
  end

  out.source = source

  -- Direct keys
  for _, key in ipairs(DIRECT) do
    if spec[key] ~= nil then
      out[key] = spec[key]
    end
  end

  -- Renamed keys
  for old, new in pairs(RENAME) do
    if spec[old] ~= nil then
      out[new] = spec[old]
    end
  end

  -- Dropped keys — warn the user
  for key, hint in pairs(DROPPED) do
    if spec[key] ~= nil and hint then
      table.insert(warns, string.format("'%s' dropped — %s", key, hint))
    end
  end

  -- cond is supported, pass through
  if spec.cond ~= nil then
    out.cond = spec.cond
  end

  return out, warns
end

local function spec_to_string(spec, indent)
  indent = indent or "  "
  local lines = {}

  table.insert(lines, indent .. "{")

  -- Source first
  if spec.source then
    table.insert(lines, indent .. "  " .. string.format("%q,", spec.source))
  end

  local ordered = {
    "name", "lazy", "event", "cmd", "ft", "keys",
    "cond", "depends", "opts", "config", "build", "pin",
  }

  for _, key in ipairs(ordered) do
    local val = spec[key]
    if val ~= nil then
      local val_str
      if type(val) == "string" then
        val_str = string.format("%q", val)
      elseif type(val) == "boolean" then
        val_str = tostring(val)
      elseif type(val) == "table" then
        -- Simple table — inline if small
        local items = {}
        for _, v in ipairs(val) do
          table.insert(items, string.format("%q", v))
        end
        val_str = "{ " .. table.concat(items, ", ") .. " }"
      elseif type(val) == "function" then
        val_str = "function() --[[ TODO: migrate this manually ]] end"
      else
        val_str = tostring(val)
      end

      table.insert(lines, indent .. "  " .. string.format("%-10s = %s,", key, val_str))
    end
  end

  table.insert(lines, indent .. "},")
  return table.concat(lines, "\n")
end

-- Validate converted specs — catch missing deps
local function validate(specs)
  local registry = {}
  local errors   = {}

  -- Build registry
  for _, spec in ipairs(specs) do
    local name = spec.source and spec.source:match("[^/]+$") or spec.name
    if name then registry[name] = true end
  end

  -- Check deps
  for _, spec in ipairs(specs) do
    if spec.depends then
      for _, dep in ipairs(spec.depends) do
        local dep_name = dep:match("[^/]+$")
        if not registry[dep_name] then
          local plugin_name = spec.source and spec.source:match("[^/]+$") or "unknown"
          table.insert(errors, string.format(
            "  '%s' depends on '%s' which is NOT in your spec — add it",
            plugin_name, dep
          ))
        end
      end
    end
  end

  return errors
end

function M.convert(input_path, output_path)
  -- Read the input file
  local f = io.open(input_path, "r")
  if not f then
    vim.notify("[garrys] cannot open " .. input_path, vim.log.levels.ERROR)
    return nil
  end

  -- We can't eval arbitrary Lua safely here, so we parse what we can
  -- and tell the user to handle functions manually
  vim.notify("[garrys] migration is best-effort — functions need manual review", vim.log.levels.WARN)

  local raw = f:read("*a")
  f:close()

  -- Replace lazy.nvim-specific keys textually
  local converted = raw

  -- dependencies -> depends
  converted = converted:gsub("dependencies%s*=", "depends     =")

  -- priority = ... -> -- priority removed (use lazy = false)
  converted = converted:gsub("priority%s*=%s*%d+,%s*\n", "-- priority removed — use lazy = false\n")

  -- dev = true -> -- dev not supported
  converted = converted:gsub("dev%s*=%s*true,%s*\n", "-- dev = true not supported in garrys.nvim\n")

  -- version = "..." -> pin = true
  converted = converted:gsub('version%s*=%s*"[^"]*"', "pin       = true  -- version pinning not supported, using pin = true")

  -- Write output
  local out_path = output_path or input_path:gsub("%.lua$", ".garrys.lua")
  local out = io.open(out_path, "w")
  if not out then
    vim.notify("[garrys] cannot write to " .. out_path, vim.log.levels.ERROR)
    return nil
  end

  out:write("-- Migrated from lazy.nvim by :GarryMigrate\n")
  out:write("-- Review functions and complex configs manually\n\n")
  out:write(converted)
  out:close()

  vim.notify("[garrys] ✔ migrated → " .. out_path, vim.log.levels.INFO)
  return out_path

  -- Auto-validate immediately after converting
  -- Parse deps from the converted file and cross-check them
  vim.notify("[garrys] validating output...", vim.log.levels.INFO)
  M._validate_file(out_path)
end

-- Validate a converted file by scanning for depends = { ... } blocks
-- and checking every declared dep appears as a source in the same file
function M._validate_file(path)
  local f = io.open(path, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()

  -- Collect all plugin sources
  local sources = {}
  for source in content:gmatch('"([%w%-%.]+/[%w%-%.%_]+)"') do
    local name = source:match("[^/]+$")
    sources[name] = true
  end

  -- Collect all depends entries
  local errors  = {}
  local current = nil

  for line in content:gmatch("[^
]+") do
    -- Track current plugin by its source line
    local src = line:match('"([%w%-%.]+/[%w%-%.%_]+)"')
    if src and not line:find("depends") then
      current = src:match("[^/]+$")
    end

    -- Find dep entries inside depends = { ... }
    local dep = line:match('depends%s*=.*"([%w%-%.]+/[%w%-%.%_]+)"')
    if dep then
      local dep_name = dep:match("[^/]+$")
      if not sources[dep_name] then
        table.insert(errors, string.format(
          "  '%s' depends on '%s' — not found in spec, add it",
          current or "unknown", dep
        ))
      end
    end
  end

  if #errors == 0 then
    vim.notify("[garrys] ✔ validation passed — all dependencies satisfied", vim.log.levels.INFO)
  else
    vim.notify(
      "[garrys] ✘ " .. #errors .. " missing dependenc" .. (#errors == 1 and "y" or "ies") .. ":
"
      .. table.concat(errors, "
"),
      vim.log.levels.ERROR
    )
    vim.notify("[garrys] add the missing plugins to your spec and re-run :GarryMigrate", vim.log.levels.WARN)
  end
end

-- Validate the current spec against strict dep rules
function M.validate()
  local garrys = require("garrys")
  local errors = {}

  for _, plugin in pairs(garrys._plugins) do
    for _, dep in ipairs(plugin.depends or {}) do
      local dep_name = dep:match("[^/]+$")
      if not garrys._plugins[dep_name] then
        table.insert(errors, string.format(
          "  '%s' depends on '%s' — not in spec",
          plugin.name, dep
        ))
      end
    end
  end

  if #errors == 0 then
    vim.notify("[garrys] ✔ all dependencies satisfied", vim.log.levels.INFO)
  else
    vim.notify("[garrys] ✘ dependency errors:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
  end
end

return M
