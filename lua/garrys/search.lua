local M = {}

-- Search GitHub for Neovim plugins
function M.search(query, callback)
  local q   = vim.uri_encode(query .. " neovim plugin")
  local url = "https://api.github.com/search/repositories?q=" .. q
              .. "&sort=stars&order=desc&per_page=10"

  vim.system(
    { "curl", "-sf", "--max-time", "8",
      "-H", "Accept: application/vnd.github+json",
      url },
    { text = true },
    function(result)
      if result.code ~= 0 then
        callback(nil, "curl failed — are you online?")
        return
      end

      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok or not data.items then
        callback(nil, "GitHub API error")
        return
      end

      local results = {}
      for _, item in ipairs(data.items) do
        table.insert(results, {
          full_name   = item.full_name,
          description = item.description or "",
          stars       = item.stargazers_count or 0,
          url         = item.html_url,
        })
      end

      callback(results, nil)
    end
  )
end

-- Show results in a picker (vim.ui.select or telescope if available)
function M.pick(query)
  local u = require("garrys.util")

  if not query or query == "" then
    u.warn("usage: :GarrySearch <query>")
    return
  end

  u.info("searching for '" .. query .. "'...")

  M.search(query, function(results, err)
    if err then
      vim.schedule(function() u.err(err) end)
      return
    end

    if #results == 0 then
      vim.schedule(function() u.info("no results for '" .. query .. "'") end)
      return
    end

    vim.schedule(function()
      local items = {}
      for _, r in ipairs(results) do
        table.insert(items, string.format(
          "%-40s  ★ %-6d  %s",
          r.full_name,
          r.stars,
          r.description:sub(1, 50)
        ))
      end

      vim.ui.select(items, {
        prompt = "garrys.nvim — install plugin:",
        format_item = function(item) return item end,
      }, function(choice, idx)
        if not choice or not idx then return end

        local picked = results[idx]
        local source = picked.full_name

        -- Check if already installed
        local garrys = require("garrys")
        local name   = source:match("[^/]+$")

        if garrys._plugins[name] then
          u.warn(name .. " is already in your spec")
          return
        end

        -- Confirm
        vim.ui.input({
          prompt = "add to spec? [y/N] ",
        }, function(input)
          if input and input:lower() == "y" then
            -- Add to runtime spec
            garrys.plug(source)
            -- Install immediately
            local git    = require("garrys.git")
            local plugin = garrys._plugins[name]
            if plugin then
              local ui = require("garrys.ui")
              ui.open()
              ui.set_total(1)
              ui.set_status(name, "installing...")
              git.clone(plugin.url, plugin.path, function(ok, clone_err)
                vim.schedule(function()
                  if ok then
                    ui.set_status(name, "✔ installed")
                    require("garrys.loader").inject(plugin)
                  else
                    ui.set_status(name, "✘ " .. (clone_err or ""):gsub("\n", " "))
                  end
                  ui.finish()
                end)
              end)

              -- Print the spec line so user can add it to their config
              u.info(
                "add to your config:\n  { \"" .. source .. "\" }"
              )
            end
          end
        end)
      end)
    end)
  end)
end

return M
