-- Registry of multiplexer session backends.
-- Kept free of other sidekick dependencies so `sidekick.config` can use it.
local M = {}

---@class sidekick.cli.mux.Backend
---@field name string
---@field module string
---@field env string env var that is set when running inside this multiplexer

--- Ordered by detection priority
---@type sidekick.cli.mux.Backend[]
M.backends = {
  { name = "zellij", module = "sidekick.cli.session.zellij", env = "ZELLIJ" },
  { name = "herdr", module = "sidekick.cli.session.herdr", env = "HERDR_ENV" },
  { name = "tmux", module = "sidekick.cli.session.tmux", env = "TMUX" },
}

---@return string[]
function M.names()
  return vim.tbl_map(function(b)
    return b.name
  end, M.backends)
end

--- The multiplexer Neovim is running in, defaulting to tmux
function M.detect()
  for _, b in ipairs(M.backends) do
    if vim.env[b.env] then
      return b.name
    end
  end
  return "tmux"
end

return M
