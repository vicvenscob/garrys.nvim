local M = {}

-- Clone with depth=1 and blob filter for speed
function M.clone(url, path, callback)
  vim.system(
    { "git", "clone", "--depth=1", "--filter=blob:none", url, path },
    { text = true },
    function(result)
      callback(result.code == 0, result.stderr)
    end
  )
end

-- Pull with rebase + autostash so local changes don't block
function M.pull(path, callback)
  vim.system(
    { "git", "-C", path, "pull", "--rebase", "--autostash" },
    { text = true },
    function(result)
      callback(result.code == 0, result.stderr)
    end
  )
end

function M.get_commit(path, callback)
  vim.system(
    { "git", "-C", path, "rev-parse", "HEAD" },
    { text = true },
    function(result)
      local commit = result.stdout:gsub("%s+", "")
      callback(commit ~= "" and commit or nil)
    end
  )
end

function M.checkout(path, commit, callback)
  vim.system(
    { "git", "-C", path, "checkout", commit },
    { text = true },
    function(result)
      callback(result.code == 0, result.stderr)
    end
  )
end

function M.is_repo(path)
  return vim.loop.fs_stat(path .. "/.git") ~= nil
end

function M.get_remote(path, callback)
  vim.system(
    { "git", "-C", path, "remote", "get-url", "origin" },
    { text = true },
    function(result)
      callback(result.stdout:gsub("%s+", ""))
    end
  )
end

return M
