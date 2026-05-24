<div align="center">

# garrys.nvim

**A fast, no-nonsense plugin manager for Neovim 0.10+**

*Stop configuring. Write some code.*

[![Neovim](https://img.shields.io/badge/Neovim-0.10+-57A143?style=flat-square&logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1-2C2D72?style=flat-square&logo=lua&logoColor=white)](https://lua.org)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
[![Git](https://img.shields.io/badge/Git-2.19+-F05032?style=flat-square&logo=git&logoColor=white)](https://git-scm.com)

</div>

---

> *Garry's Mod shipped with everything. You spawned in and it just worked.*  
> *Then you broke it. Then you fixed it. Then you made something nobody expected.*  
>
> **garrys.nvim is that.**

---

## Features

- **Drop-in lazy.nvim replacement** — paste your existing config, it works
- **Async installs** — concurrent git clones via `vim.system()`, never blocks
- **Tabbed HUD** — Installed / Updates / Log with live progress bar
- **Plugin search** — `:GarrySearch` hits GitHub API, pick and install live
- **Startup profiler** — `:GarryProfile` ranks every plugin by load time
- **Diff view** — `:GarryDiff` shows what changed per plugin since last update
- **Lockfile** — pin every plugin to an exact commit, reproducible everywhere
- **Health checks** — `:GarryHealth` validates every plugin on disk
- **Migration tool** — `:GarryMigrate` converts lazy.nvim specs automatically
- **Auto-install** — missing plugins install on first launch, no manual step
- **Bytecode cache** — `vim.loader.enable()` called automatically
- **Strict dep graph** — opt-in validation catches undeclared dependencies
- **Retry on failure** — failed git installs retry once before giving up

---

## Requirements

| Dependency | Version |
|---|---|
| Neovim | `>= 0.10.0` (LuaJIT required) |
| Git | `>= 2.19.0` |
| Nerd Font | optional |

---

## Install

Paste this at the top of `~/.config/nvim/init.lua`:

```lua
-- Bootstrap garrys.nvim
local path = vim.fn.stdpath("data") .. "/garrys/garrys.nvim"
if not (vim.uv or vim.loop).fs_stat(path) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/ihave17bucks/garrys.nvim.git",
    path,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone garrys.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(path)
package.path = package.path .. ";" .. path .. "/lua/?.lua"
package.path = package.path .. ";" .. path .. "/lua/?/init.lua"
vim.cmd("source " .. path .. "/plugin/garrys.lua")

vim.g.mapleader      = " "
vim.g.maplocalleader = "\\"

require("garrys").setup({
  { import = "plugins" },
})
```

Open Neovim. garrys.nvim bootstraps itself, then installs your plugins automatically.

> Installs to `~/.local/share/nvim/garrys/garrys.nvim` — outside your config.  
> Remove with `rm -rf ~/.local/share/nvim/garrys`

---

## Usage

```lua
require("garrys").setup({
  { "nvim-lua/plenary.nvim" },
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
  { "neovim/nvim-lspconfig",           opts  = {}          },
  {
    "nvim-telescope/telescope.nvim",
    cmd          = "Telescope",
    dependencies = { "nvim-lua/plenary.nvim" },
  },
})
```

> **lazy.nvim users:** paste your existing spec unchanged. `dependencies`, `config`,  
> `build`, `init`, `priority`, `dev` — all silently accepted.

---

## Plugin Spec

```lua
{
  "user/repo",              -- required. github shorthand.

  -- identity
  name  = "override",       -- if the repo name sucks

  -- lazy loading (identical to lazy.nvim)
  lazy  = true,
  event = "BufReadPre",
  cmd   = "SomeCommand",
  ft    = "rust",
  keys  = "<leader>ff",
  cond  = function()        -- skip if returns false
    return vim.fn.executable("rg") == 1
  end,

  -- dependencies — lazy.nvim field name works as-is
  dependencies = { "nvim-lua/plenary.nvim" },
  dep          = { "nvim-lua/plenary.nvim" },  -- short alias

  -- configuration
  opts   = { option = true },
  config = function(opts) ... end,  -- lazy.nvim field
  on     = function(opts) ... end,  -- short alias
  init   = function() ... end,      -- runs before load (lazy.nvim compat)

  -- build hooks
  build = ":TSUpdate",   -- lazy.nvim field
  make  = ":TSUpdate",   -- short alias

  -- versioning
  pin    = true,            -- never update this plugin
  branch = "stable",        -- clone from specific branch
  tag    = "v1.0.0",        -- clone from specific tag
  update = "weekly",        -- auto-update: "daily" | "weekly" | "monthly"

  -- groups
  group = "lsp",            -- assign to a named group

  -- offline
  offline = true,           -- skip git, load from disk only

  -- stacking
  extends = "user/repo",    -- modify another plugin's opts
  patch   = function(opts)  -- called with the target's opts
    opts.something = true
    return opts
  end,

  -- misc
  dir = "~/my/plugin",      -- local plugin, added to rtp directly
  url = "git@github.com:user/repo.git",  -- custom url
}
```

---

## Multi-file Config

Drop files in `lua/plugins/` and garrys.nvim discovers them automatically:

```
~/.config/nvim/
├── init.lua
└── lua/plugins/
    ├── ui.lua       -- return { { "catppuccin/nvim", ... }, ... }
    ├── lsp.lua      -- return { { "neovim/nvim-lspconfig" }, ... }
    ├── tools.lua    -- return { { "nvim-telescope/telescope.nvim", ... } }
    └── coding.lua   -- return { { "hrsh7th/nvim-cmp", ... } }
```

Same as lazy.nvim's `{ import = "plugins" }`.

---

## Commands

| Command | Description |
|---|---|
| `:GarryInstall` | Install every missing plugin |
| `:GarryInstall user/repo` | Install a specific plugin |
| `:GarryUpdate` | Pull updates for all plugins |
| `:GarryUpdate user/repo` | Update a specific plugin |
| `:GarryAdd user/repo` | Install a plugin live without editing your config |
| `:GarryClean` | Delete plugins not in your spec |
| `:GarryStatus` | Open tabbed HUD — Installed / Updates / Log |
| `:GarryGroup` | List all plugin groups |
| `:GarryGroup <name> on/off` | Enable or disable a plugin group |
| `:GarryLock` | Write `garrys.lock` — pin every plugin to current commit |
| `:GarryRestore` | Roll back every plugin to its locked commit |
| `:GarryHealth` | Check every plugin — on disk, valid repo, loadable, require() |
| `:GarryProfile` | Rank plugins by startup load time (persists across sessions) |
| `:GarryDiff` | Show what changed per plugin since last update |
| `:GarrySearch <query>` | Search GitHub, pick a result, install live |
| `:GarryMigrate [file]` | Convert lazy.nvim spec + validate deps |
| `:GarryValidate` | Check all declared deps are in your spec |
| `:GarryList` | Sorted list with flags — loaded, lazy, pinned, group, offline |

---

## The UI

```
╭─────────────────────────────────────────────────────────────╮
│                        garrys.nvim                          │
│                     4 plugins   0.84s                       │
│                                                             │
│       Installed        Updates          Log                 │
│                                                             │
│   ✔  plenary.nvim               installed                   │
│   ✔  nvim-treesitter            installed                   │
│   ▶  nvim-lspconfig             installing…                 │
│   ○  telescope.nvim             missing                     │
│                                                             │
│   ████████████████████████████░░░░░░░░░░   75%             │
│   4 plugins  ·  2 ok  ·  1 active                          │
│   q close  ·  ? help                                        │
╰─────────────────────────────────────────────────────────────╯
```

**Keys:** `1` `2` `3` switch tabs · `<Tab>` cycle · `j`/`k` navigate · `u` update · `i` install · `r` health · `?` help · `q` close

---

## Lockfile

```json
{
  "plenary.nvim": {
    "commit": "a3e3bc82a3f95c5ed0d7201546d5d2ece00051c6",
    "url": "https://github.com/nvim-lua/plenary.nvim.git"
  }
}
```

`:GarryLock` to write it. `:GarryRestore` to roll back. Commit it to your dotfiles.

---

## Migrating from lazy.nvim

```vim
:GarryMigrate
```

Auto-detects your lazy.nvim spec, converts field names, validates deps, reports exactly what's missing. One command, done.

**Field mapping:**

| lazy.nvim | garrys.nvim | notes |
|---|---|---|
| `dependencies` | `dep` | both accepted |
| `config` | `on` | both accepted |
| `build` | `make` | both accepted |
| `init` | `init` | identical |
| `priority = 1000` | `lazy = false` | silently accepted |
| `version = "^1.0"` | `pin = true` | silently accepted |
| `dev = true` | — | silently ignored |

---

## How It Works

```
setup()
  └── normalize specs (lazy.nvim compat, 1:1)
  └── auto-discover lua/plugins/*.lua
  └── optional strict dep validation
  └── loader.load_all()
        └── vim.loader.enable()           -- bytecode cache, free speedup
        └── sort by dependency graph
        └── eager  → inject into rtp immediately
        └── lazy   → register autocmd / stub command / keymap
  └── autoinstall missing on VimEnter (with retry)
```

---

## File Structure

```
garrys.nvim/
├── lua/garrys/
│   ├── init.lua       -- setup(), plug(), load(), autoinstall
│   ├── git.lua        -- clone, pull, get_commit, checkout
│   ├── loader.lua     -- rtp injection, lazy loading, bytecode cache
│   ├── lockfile.lua   -- write, read, restore garrys.lock
│   ├── ui.lua         -- tabbed HUD, progress bar, keymaps
│   ├── util.lua       -- logging, path helpers, dep sorting
│   ├── profile.lua    -- startup time tracking per plugin
│   ├── diff.lua       -- git log since last update
│   ├── search.lua     -- GitHub API search + install
│   ├── migrate.lua    -- lazy.nvim spec conversion + validation
│   └── addon/
│       └── lua.lua    -- EmmyLua type annotations for lua-ls
└── plugin/
    └── garrys.lua     -- all user commands (auto-sourced from rtp)
```

---

## vs lazy.nvim

| | lazy.nvim | garrys.nvim |
|---|---|---|
| Lines of code | ~5000+ | ~800 |
| lazy.nvim spec compat | native | ✔ 1:1 |
| Bytecode caching | ✔ | ✔ |
| Lazy loading | ✔ | ✔ |
| Lockfile | ✔ | ✔ |
| Tabbed UI | ✔ | ✔ |
| Plugin search | ✘ | ✔ `:GarrySearch` |
| Startup profiler | ✔ | ✔ `:GarryProfile` |
| Diff view | ✘ | ✔ `:GarryDiff` |
| Health checks | ✘ | ✔ `:GarryHealth` |
| Migration tool | ✘ | ✔ `:GarryMigrate` |
| Retry on failed install | ✘ | ✔ |
| Strict dep graph | ✘ | ✔ opt-in |
| Rockspec | ✔ | no, and proud of it |
| Neovim target | 0.8+ | **0.10+ only** |

---

## Part of the Garry's Ecosystem

garrys.nvim is the engine under **GarryVim** — a full Neovim distribution built on this plugin manager with an addon system, LSP, formatting, and linting configured out of the box.

garrys.nvim stands alone. You don't need GarryVim to use it.

---

## License

MIT — do whatever. Just don't blame me when you break it.

---

<div align="center">

*built with Neovim · on Arch · at an unreasonable hour*

</div>
