-- garrys.nvim — ui.lua
-- Clean, performant, lazy.nvim-style floating window UI

local M   = {}
local api = vim.api

-- ── Constants ──────────────────────────────────────────────────────────────

local CFG = {
  width      = 70,
  min_height = 12,
  max_height = 40,
  interval   = 100,
  spinner    = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  tabs       = { "installed", "updates", "log" },
  tab_labels = { "  Installed  ", "  Updates  ", "  Log  " },
}

local ICONS = {
  done      = " ",
  failed    = " ",
  installed = " ",
  missing   = "○ ",
  lazy      = "󰒲 ",
  pin       = " ",
  unknown   = "· ",
}

-- ── Theme ──────────────────────────────────────────────────────────────────

local THEME = {
  title      = "GarrysTitle",
  subtitle   = "GarrysSub",
  tab_active = "GarrysTabActive",
  tab_normal = "GarrysTabNormal",
  ok         = "GarrysOk",
  err        = "GarrysErr",
  active     = "GarrysActive",
  dim        = "GarrysDim",
  bar_fill   = "GarrysBarFill",
  bar_empty  = "GarrysBarEmpty",
  pct        = "GarrysPct",
  name       = "GarrysName",
  msg        = "GarrysMsg",
  footer     = "GarrysFooter",
  cursor     = "GarrysCursor",
}

local function setup_highlights()
  local hl = vim.api.nvim_set_hl
  hl(0, THEME.title,      { fg = "#cba6f7", bold = true })
  hl(0, THEME.subtitle,   { fg = "#7f849c" })
  hl(0, THEME.tab_active, { fg = "#cba6f7", bold = true, underline = true })
  hl(0, THEME.tab_normal, { fg = "#585b70" })
  hl(0, THEME.ok,         { fg = "#a6e3a1", bold = true })
  hl(0, THEME.err,        { fg = "#f38ba8", bold = true })
  hl(0, THEME.active,     { fg = "#89b4fa", bold = true })
  hl(0, THEME.dim,        { fg = "#45475a" })
  hl(0, THEME.bar_fill,   { fg = "#cba6f7" })
  hl(0, THEME.bar_empty,  { fg = "#313244" })
  hl(0, THEME.pct,        { fg = "#f5c2e7", bold = true })
  hl(0, THEME.name,       { fg = "#cdd6f4" })
  hl(0, THEME.msg,        { fg = "#6c7086" })
  hl(0, THEME.footer,     { fg = "#585b70", italic = true })
  hl(0, THEME.cursor,     { bg = "#313244" })
end

-- ── State ──────────────────────────────────────────────────────────────────

local S = {
  buf        = nil,
  win        = nil,
  timer      = nil,
  tick       = 0,
  tab        = "installed",
  cursor     = 1,
  plugins    = {},
  log        = {},
  total      = 0,
  done       = 0,
  done_set   = {},
  start_time = nil,
  elapsed    = nil,
  footer     = "q close  ·  ? help",
  dirty      = true,
  last_h     = 0,
}

-- ── Helpers ────────────────────────────────────────────────────────────────

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function truncate(s, max)
  if vim.fn.strdisplaywidth(s) <= max then return s end
  return s:sub(1, max - 1) .. "…"
end

local function pad_right(s, w)
  local len = vim.fn.strdisplaywidth(s)
  if len >= w then return truncate(s, w) end
  return s .. string.rep(" ", w - len)
end

local function center_str(s, w)
  local len = vim.fn.strdisplaywidth(s)
  local p   = math.max(0, w - len)
  return string.rep(" ", math.floor(p / 2)) .. s .. string.rep(" ", math.ceil(p / 2))
end

local function get_elapsed()
  if S.elapsed    then return string.format("%.2fs", S.elapsed) end
  if S.start_time then return string.format("%.2fs", (vim.loop.hrtime() - S.start_time) / 1e9) end
  return ""
end

local function spinner() return CFG.spinner[((S.tick - 1) % #CFG.spinner) + 1] end

local function sorted_plugins()
  local order = { installing = 0, updating = 0, failed = 1, done = 2, installed = 3, missing = 4, info = 5 }
  local list  = {}
  for name, entry in pairs(S.plugins) do
    table.insert(list, { name = name, entry = entry })
  end
  table.sort(list, function(a, b)
    local oa = order[a.entry.state] or 9
    local ob = order[b.entry.state] or 9
    if oa ~= ob then return oa < ob end
    return a.name < b.name
  end)
  return list
end

-- ── Row builders ───────────────────────────────────────────────────────────
-- Each row: { text, hl = { {group, s, e} }, type, cursor? }

local function spacer() return { text = "", hl = {}, type = "spacer" } end

local function build_header()
  local W    = CFG.width
  local rows = {}

  local elapsed = get_elapsed()
  local sub     = S.total .. (S.total == 1 and " plugin" or " plugins")
  if elapsed ~= "" then sub = sub .. "   " .. elapsed end

  table.insert(rows, {
    text = center_str("garrys.nvim", W),
    hl   = { { THEME.title, 0, -1 } },
    type = "title",
  })
  table.insert(rows, {
    text = center_str(sub, W),
    hl   = { { THEME.subtitle, 0, -1 } },
    type = "subtitle",
  })
  table.insert(rows, spacer())

  -- Tabs
  local total_w = 0
  for _, l in ipairs(CFG.tab_labels) do total_w = total_w + #l + 2 end
  local pad     = math.max(0, math.floor((W - total_w) / 2))
  local text    = string.rep(" ", pad)
  local hls     = {}
  local col     = pad

  for i, id in ipairs(CFG.tabs) do
    local label  = CFG.tab_labels[i]
    local is_cur = S.tab == id
    local chunk  = " " .. label .. " "
    table.insert(hls, { is_cur and THEME.tab_active or THEME.tab_normal, col, col + #chunk })
    text = text .. chunk
    col  = col + #chunk
  end

  table.insert(rows, { text = text, hl = hls, type = "tabs" })
  table.insert(rows, spacer())

  return rows
end

local function build_plugin_row(i, name, entry, tab)
  local W      = CFG.width
  local icon, icon_hl

  if entry.state == "installing" or entry.state == "updating" then
    icon    = spinner() .. " "
    icon_hl = THEME.active
  elseif entry.state == "done" then
    icon    = ICONS.done
    icon_hl = THEME.ok
  elseif entry.state == "failed" then
    icon    = ICONS.failed
    icon_hl = THEME.err
  elseif entry.state == "installed" then
    icon    = entry.pin and ICONS.pin or (entry.lazy and ICONS.lazy or ICONS.installed)
    icon_hl = entry.pin and THEME.dim or THEME.ok
  elseif entry.state == "missing" then
    icon    = ICONS.missing
    icon_hl = THEME.dim
  else
    icon    = ICONS.unknown
    icon_hl = THEME.dim
  end

  local name_w  = 30
  local msg_w   = W - name_w - 6 - #icon
  local name_s  = pad_right(truncate(name, name_w), name_w)
  local msg_s   = truncate(entry.msg or "", math.max(0, msg_w))
  local text    = "  " .. icon .. " " .. name_s .. "  " .. msg_s
  local is_cur  = (S.tab == tab and i == S.cursor)

  -- byte offsets for highlights
  local icon_s  = 2
  local icon_e  = icon_s + #icon
  local name_s_ = icon_e + 1
  local name_e  = name_s_ + #name_s
  local msg_s_  = name_e + 2

  return {
    text   = text,
    hl     = {
      { icon_hl,    icon_s,  icon_e },
      { THEME.name, name_s_, name_e },
      { THEME.msg,  msg_s_,  -1     },
    },
    type   = "plugin",
    index  = i,
    cursor = is_cur,
  }
end

local function build_installed_tab()
  local rows = {}
  local list = sorted_plugins()

  if #list == 0 then
    return { { text = center_str("no plugins registered", CFG.width), hl = { { THEME.dim, 0, -1 } }, type = "empty" } }
  end

  for i, item in ipairs(list) do
    table.insert(rows, build_plugin_row(i, item.name, item.entry, "installed"))
  end
  return rows
end

local function build_updates_tab()
  local rows = {}
  local list = sorted_plugins()

  if #list == 0 then
    return { { text = center_str("no plugins", CFG.width), hl = { { THEME.dim, 0, -1 } }, type = "empty" } }
  end

  for i, item in ipairs(list) do
    local e     = vim.tbl_extend("force", item.entry, {})
    e.msg       = item.entry.lazy and "lazy" or (item.entry.pin and "pinned" or "eager")
    table.insert(rows, build_plugin_row(i, item.name, e, "updates"))
  end
  return rows
end

local function build_log_tab()
  if #S.log == 0 then
    return { { text = center_str("no log entries", CFG.width), hl = { { THEME.dim, 0, -1 } }, type = "empty" } }
  end

  local rows = {}
  local max  = CFG.max_height - 12
  local from = math.max(1, #S.log - max + 1)

  for i = from, #S.log do
    local entry    = S.log[i]
    local icon_hl  = entry.ok and THEME.ok or THEME.err
    local icon     = entry.ok and ICONS.done or ICONS.failed
    local time_s   = entry.time
    local msg_w    = CFG.width - #time_s - #icon - 8
    local text     = "  " .. time_s .. "   " .. icon .. " " .. truncate(entry.msg, msg_w)
    local icon_col = 2 + #time_s + 3
    table.insert(rows, {
      text = text,
      hl   = {
        { THEME.dim,  2, 2 + #time_s },
        { icon_hl,    icon_col, icon_col + #icon },
        { THEME.msg,  icon_col + #icon + 1, -1 },
      },
      type = "log",
    })
  end
  return rows
end

local function build_footer()
  local rows = {}
  local W    = CFG.width

  -- Progress bar — only on installed tab
  if S.tab == "installed" and S.total > 0 then
    local bar_w  = 40
    local filled = math.floor(clamp(S.done / S.total, 0, 1) * bar_w)
    local pct_s  = math.floor(clamp(S.done / S.total, 0, 1) * 100) .. "%"
    local bar    = string.rep("█", filled) .. string.rep("░", bar_w - filled)
    local line   = "  " .. bar .. "  " .. pct_s

    table.insert(rows, spacer())
    table.insert(rows, {
      text = line,
      hl   = {
        { THEME.bar_fill,  2,           2 + filled },
        { THEME.bar_empty, 2 + filled,  2 + bar_w  },
        { THEME.pct,       2 + bar_w + 2, -1       },
      },
      type = "bar",
    })
  end

  -- Stats
  local done_ct, fail_ct, active_ct = 0, 0, 0
  for _, e in pairs(S.plugins) do
    if     e.state == "done" or e.state == "installed" then done_ct   = done_ct   + 1
    elseif e.state == "failed"                          then fail_ct   = fail_ct   + 1
    elseif e.state == "installing" or e.state == "updating" then active_ct = active_ct + 1
    end
  end

  local parts = {}
  if S.total    > 0 then table.insert(parts, S.total    .. " plugins") end
  if done_ct    > 0 then table.insert(parts, done_ct    .. " ok")      end
  if fail_ct    > 0 then table.insert(parts, fail_ct    .. " failed")  end
  if active_ct  > 0 then table.insert(parts, active_ct  .. " active")  end

  if #parts > 0 then
    table.insert(rows, {
      text = "  " .. table.concat(parts, "  ·  "),
      hl   = { { THEME.subtitle, 0, -1 } },
      type = "stats",
    })
  end

  table.insert(rows, {
    text = "  " .. S.footer,
    hl   = { { THEME.footer, 0, -1 } },
    type = "footer",
  })

  return rows
end

-- ── Render ─────────────────────────────────────────────────────────────────

local function render()
  if not S.buf or not api.nvim_buf_is_valid(S.buf) then return end
  if not S.dirty then return end
  S.dirty = false

  local rows = {}
  table.insert(rows, spacer())
  for _, r in ipairs(build_header())       do table.insert(rows, r) end

  local tab_rows
  if     S.tab == "installed" then tab_rows = build_installed_tab()
  elseif S.tab == "updates"   then tab_rows = build_updates_tab()
  else                             tab_rows = build_log_tab() end

  for _, r in ipairs(tab_rows)             do table.insert(rows, r) end
  table.insert(rows, spacer())
  for _, r in ipairs(build_footer())       do table.insert(rows, r) end
  table.insert(rows, spacer())

  local lines = vim.tbl_map(function(r) return r.text end, rows)

  vim.bo[S.buf].modifiable = true
  api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false

  -- Highlights
  api.nvim_buf_clear_namespace(S.buf, -1, 0, -1)
  for i, r in ipairs(rows) do
    local li = i - 1
    if r.cursor then
      pcall(api.nvim_buf_add_highlight, S.buf, -1, THEME.cursor, li, 0, -1)
    end
    for _, h in ipairs(r.hl or {}) do
      pcall(api.nvim_buf_add_highlight, S.buf, -1, h[1], li, h[2], h[3])
    end
  end

  -- Resize only when height changes
  local new_h = clamp(#lines, CFG.min_height, CFG.max_height)
  if new_h ~= S.last_h and S.win and api.nvim_win_is_valid(S.win) then
    api.nvim_win_set_height(S.win, new_h)
    S.last_h = new_h
  end
end

-- ── Timer ──────────────────────────────────────────────────────────────────

local function start_timer()
  if S.timer then return end
  S.timer = vim.loop.new_timer()
  S.timer:start(0, CFG.interval, vim.schedule_wrap(function()
    S.tick = S.tick + 1
    local has_active = false
    for _, e in pairs(S.plugins) do
      if e.state == "installing" or e.state == "updating" then
        has_active = true; break
      end
    end
    if has_active then S.dirty = true; render() end
  end))
end

local function stop_timer()
  if S.timer then
    S.timer:stop(); S.timer:close(); S.timer = nil
  end
end

-- ── Keymaps ────────────────────────────────────────────────────────────────

local function setup_keymaps()
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = S.buf, silent = true, nowait = true })
  end

  map("q",     function() M.close() end)
  map("<Esc>", function() if #api.nvim_list_wins() > 1 then M.close() end end)

  map("<Tab>", function()
    local idx = 1
    for i, id in ipairs(CFG.tabs) do if id == S.tab then idx = i; break end end
    S.tab    = CFG.tabs[(idx % #CFG.tabs) + 1]
    S.cursor = 1; S.dirty = true; render()
  end)

  for i, id in ipairs(CFG.tabs) do
    local _id = id
    map(tostring(i), function()
      S.tab = _id; S.cursor = 1; S.dirty = true; render()
    end)
  end

  map("j", function()
    S.cursor = clamp(S.cursor + 1, 1, math.max(1, vim.tbl_count(S.plugins)))
    S.dirty  = true; render()
  end)
  map("k", function()
    S.cursor = clamp(S.cursor - 1, 1, math.max(1, vim.tbl_count(S.plugins)))
    S.dirty  = true; render()
  end)

  map("u", function() M.close(); vim.cmd("GarryUpdate")  end)
  map("i", function() M.close(); vim.cmd("GarryInstall") end)
  map("r", function() M.close(); vim.cmd("GarryHealth")  end)

  map("?", function()
    S.footer = "i install  u update  r health  1/2/3 tabs  j/k nav  q close"
    S.dirty  = true; render()
  end)
end

-- ── Public API ─────────────────────────────────────────────────────────────

function M.open()
  if S.win and api.nvim_win_is_valid(S.win) then return end

  setup_highlights()

  S.buf       = api.nvim_create_buf(false, true)
  S.plugins   = {}
  S.log       = {}
  S.total     = 0
  S.done      = 0
  S.done_set  = {}
  S.start_time = vim.loop.hrtime()
  S.elapsed   = nil
  S.footer    = "q close  ·  ? help"
  S.dirty     = true
  S.cursor    = 1
  S.last_h    = 0
  S.tab       = S.tab or "installed"  -- remember last tab

  vim.bo[S.buf].filetype   = "garrys"
  vim.bo[S.buf].modifiable = false
  vim.bo[S.buf].bufhidden  = "wipe"
  vim.bo[S.buf].buftype    = "nofile"

  local w   = math.min(CFG.width, vim.o.columns - 4)
  local h   = CFG.min_height
  local row = math.floor((vim.o.lines - h) / 2)
  local col = math.floor((vim.o.columns - w) / 2)

  S.win = api.nvim_open_win(S.buf, true, {
    relative  = "editor",
    width     = w,
    height    = h,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    zindex    = 50,
    title     = " garrys.nvim ",
    title_pos = "center",
  })

  vim.wo[S.win].wrap       = false
  vim.wo[S.win].cursorline = true
  vim.wo[S.win].number     = false
  vim.wo[S.win].signcolumn = "no"
  vim.wo[S.win].foldcolumn = "0"

  setup_keymaps()
  render()
  start_timer()
end

function M.set_total(n)
  S.total = n
  S.dirty = true
end

function M.set_status(name, status)
  local entry = S.plugins[name] or {}

  if status:find("installing") then
    entry.state = "installing"
    entry.msg   = "installing…"
  elseif status:find("updating") then
    entry.state = "updating"
    entry.msg   = "updating…"
  elseif status:find("✔") or status:find("✓") then
    entry.state = "done"
    entry.msg   = status:gsub("[✔✓]%s*", ""):gsub("^%s+", "")
    if not S.done_set[name] then
      S.done_set[name] = true
      S.done           = S.done + 1
    end
    table.insert(S.log, { time = os.date("%H:%M:%S"), ok = true,  msg = name .. "  " .. (entry.msg ~= "" and entry.msg or "done") })
  elseif status:find("✘") or status:find("✗") then
    entry.state = "failed"
    entry.msg   = status:gsub("[✘✗]%s*", ""):gsub("^%s+", "")
    if not S.done_set[name] then
      S.done_set[name] = true
      S.done           = S.done + 1
    end
    table.insert(S.log, { time = os.date("%H:%M:%S"), ok = false, msg = name .. "  " .. (entry.msg or "failed") })
  else
    entry.state = "info"
    entry.msg   = status
  end

  S.plugins[name] = entry
  S.dirty         = true
  render()
end

function M.finish()
  if S.start_time then
    S.elapsed = (vim.loop.hrtime() - S.start_time) / 1e9
  end
  S.footer = "done  ·  q close  ·  ? help"
  S.dirty  = true
  stop_timer()
  render()
end

function M.close()
  stop_timer()
  if S.win and api.nvim_win_is_valid(S.win) then
    api.nvim_win_close(S.win, true)
  end
  if S.buf and api.nvim_buf_is_valid(S.buf) then
    pcall(api.nvim_buf_delete, S.buf, { force = true })
  end
  S.win = nil
  S.buf = nil
end

function M.open_status(plugins)
  M.open()
  S.total   = vim.tbl_count(plugins)
  S.done    = 0
  S.elapsed = vim.loop.hrtime() / 1e9
  S.footer  = "q close  ·  ? help  ·  u update  ·  i install"

  for _, plugin in pairs(plugins) do
    local installed = vim.loop.fs_stat(plugin.path) ~= nil
    local lazy_flag = not not (plugin.lazy or plugin.event or plugin.cmd or plugin.ft or plugin.keys)
    S.plugins[plugin.name] = {
      state  = installed and "installed" or "missing",
      msg    = lazy_flag and "lazy" or "eager",
      lazy   = lazy_flag,
      pin    = plugin.pin or false,
      loaded = plugin._loaded or false,
    }
    if installed then
      S.done = S.done + 1
      S.done_set[plugin.name] = true
    end
  end

  S.dirty = true
  stop_timer()
  render()
end

return M
