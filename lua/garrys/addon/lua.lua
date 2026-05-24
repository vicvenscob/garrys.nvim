-- garrys.nvim Lua addon
-- Teaches lua-language-server the full garrys.nvim API
-- Load this via lazydev.nvim or manually in your lua-ls config

---@meta garrys

---@class GarryPlugin
---@field [1] string          GitHub shorthand "user/repo"
---@field name?     string    Override the plugin name
---@field lazy?     boolean   Don't load on startup (default: false)
---@field event?    string|string[]  Load on this autocmd event
---@field cmd?      string|string[]  Load when this command is called
---@field ft?       string|string[]  Load for this filetype
---@field keys?     string|string[]  Load when this key is pressed
---@field cond?     boolean|fun():boolean  Skip plugin if false
---@field dep?      string[]  Plugins that must load first
---@field opts?     table     Passed to plugin's setup()
---@field on?       fun(opts: table)  Called after plugin loads
---@field make?     string|fun()  Run after install
---@field pin?      boolean   Never update this plugin

---@class GarryConfig
---@field path?        string   Where plugins are installed
---@field lockfile?    string   Path to garrys.lock
---@field concurrency? integer  Max parallel git ops (default: 8)
---@field autoinstall? boolean  Install missing plugins on startup (default: true)
---@field strict_deps? boolean  Error on undeclared deps (default: true)
---@field plugin_dir?  string   Auto-discover specs from this dir

---The main garrys.nvim module
---@class Garrys
local M = {}

---Register a plugin
---@param spec string|GarryPlugin
---@return Garrys  -- chainable
function M.plug(spec) end

---Finalize setup and start loading plugins
---@param opts? GarryConfig
function M.load(opts) end

---Legacy: register and load all at once
---@param specs GarryPlugin[]
---@param opts? GarryConfig
function M.setup(specs, opts) end

---Returns true if any plugin is missing from disk
---@return boolean
function M.has_missing() end

---Internal plugin registry
---@type table<string, GarryPlugin>
M._plugins = {}

---Internal load time registry (name -> ms)
---@type table<string, number>
M._load_times = {}

return M
