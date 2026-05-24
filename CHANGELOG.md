# Changelog

## v0.4.0 — 2026

### New Features
- **Plugin groups** — `group = "lsp"` tags a plugin, `:GarryGroup lsp off` disables the whole set
- **Branch/tag pinning** — `branch = "stable"` or `tag = "v1.0.0"` in your spec
- **Offline mode** — `offline = true` skips all git ops and loads from disk only
- **Auto-update schedule** — `update = "weekly"` fires 3 seconds after startup if the interval has passed
- **Plugin stacking** — `extends = "user/repo"` + `patch = function(opts) ... end` to modify another plugin's opts
- **`:GarryInstall user/repo`** — install a specific plugin from the cmdline
- **`:GarryUpdate user/repo`** — update a specific plugin
- **`:GarryAdd user/repo`** — add and install a plugin live without editing your config
- **`:GarryGroup`** — list, enable, disable plugin groups
- **Profile persistence** — startup times saved to disk, available across sessions

### Fixes
- `config` / `on` no longer runs if the plugin isn't installed on disk
- `{ import = "plugins" }` silently skipped instead of warning
- `:GarryUpdate` now shows commit count of what changed per plugin
- `:GarryRestore` handles branch/tag pins correctly
- `:GarryClean` removes stale schedule entries for deleted plugins
- `:GarryList` sorted alphabetically with full flag display
- Auto-setup tries multiple module name patterns before failing
- `:GarryHealth` tries multiple require patterns per plugin
- Retry on failed git clone before marking as failed
- `vim.notify` spam batched into single message per level on startup

### Breaking Changes
- None — all lazy.nvim specs still work unchanged

---

## v0.3.0

### New Features
- Tabbed HUD — Installed / Updates / Log
- `j`/`k` navigation in UI
- `?` help key
- `u`, `i`, `r` shortcuts inside UI window
- Native rounded border (`border = "rounded"`)
- UI only redraws when state changes

### Fixes
- Window focus fixed — keymaps now actually work
- `_done` counter no longer double-increments for same plugin
- Plugins sorted consistently in UI
- Long names truncated with `…`

---

## v0.2.0

### New Features
- `:GarrySearch` — GitHub API search + live install
- `:GarryDiff` — git log since last update
- `:GarryProfile` — startup time per plugin
- `:GarryMigrate` — lazy.nvim spec conversion + validation
- `:GarryValidate` — dep graph validation
- Multi-file config — auto-discover `lua/plugins/*.lua`
- `cond` support — skip plugin if condition is false
- `strict_deps` option — opt-in dep validation
- Lockfile with `:GarryLock` / `:GarryRestore`

---

## v0.1.0

- Initial release
- Install, update, clean, lock, restore
- Lazy loading by event, cmd, ft, keys
- Auto-install on first launch
- Bootstrap snippet
