local Config = require("sidekick.config")
local Util = require("sidekick.util")

---@class sidekick.cli.muxer.Herdr: sidekick.cli.Session
---@field herdr_pane_id string
---@field herdr_pid number
local M = {}
M.__index = M
-- Herdr has no embedded mode, so sessions always live in a herdr pane
M.external = true
M.priority = 10

---@param args string[]
---@param opts? { notify?:boolean }
---@return table?
function M.api(args, opts)
  local cmd = { "herdr" }
  vim.list_extend(cmd, args)
  local _, out = Util.exec(cmd, { notify = not opts or opts.notify ~= false })
  local ok, data = pcall(vim.json.decode, out or "")
  return ok and type(data) == "table" and data.result or nil
end

---@return sidekick.cli.terminal.Cmd?
function M:start()
  if vim.env.HERDR_ENV ~= "1" then
    Util.warn("Herdr sessions can only be started when Neovim is running inside a herdr pane.")
    return
  end

  local create = Config.cli.mux.create
  if create == "terminal" then
    Util.warn({
      ("Herdr does not support `opts.cli.mux.create = %q`."):format(create),
      ("Falling back to `%q`."):format("split"),
      "Please update your config.",
    })
    create = "split"
  end

  local pane ---@type table?
  if create == "window" then
    local ret = M.api({ "tab", "create", "--cwd", self.cwd, "--label", self.tool.name, "--no-focus" })
    pane = ret and ret.root_pane
  else
    local cmd = { "pane", "split", "--current", "--cwd", self.cwd, "--no-focus" }
    vim.list_extend(cmd, { "--direction", Config.cli.mux.split.vertical and "right" or "down" })
    local ratio = self:split_ratio()
    if ratio then
      vim.list_extend(cmd, { "--ratio", tostring(ratio) })
    end
    local ret = M.api(cmd)
    pane = ret and ret.pane
  end
  if not (pane and pane.pane_id) then
    return
  end

  -- `exec` so the pane closes when the tool exits
  if not Util.exec({ "herdr", "pane", "run", pane.pane_id, "exec " .. self:shell_cmd() }) then
    return
  end
  self.herdr_pane_id = pane.pane_id
  self.mux_session = pane.pane_id
  self.started = true
  local info = M.process_info(pane.pane_id)
  if info then
    self.herdr_pid = info.shell_pid
    self.id = ("herdr %d"):format(info.shell_pid)
  end
  Util.info(("Started **%s** in a new herdr %s"):format(self.tool.name, create == "window" and "tab" or "split"))
end

--- Herdr's `--ratio` is the share kept by the current pane
---@return number?
function M:split_ratio()
  local size = Config.cli.mux.split.size
  if size <= 1 then
    return 1 - size
  end
  local ret = M.api({ "pane", "layout", "--current" }, { notify = false })
  for _, p in ipairs(ret and ret.layout and ret.layout.panes or {}) do
    if p.pane_id == vim.env.HERDR_PANE_ID then
      local total = Config.cli.mux.split.vertical and p.rect.width or p.rect.height
      return total > size and (total - size) / total or nil
    end
  end
end

--- Shell command line for the tool, including env overrides
function M:shell_cmd()
  local unset, set = {}, {} ---@type string[], string[]
  for key, value in pairs(self.tool.env or {}) do
    if value == false then
      vim.list_extend(unset, { "-u", key })
    else
      set[#set + 1] = ("%s=%s"):format(key, tostring(value))
    end
  end
  -- `env` options must come before any assignments
  local cmd = (#unset + #set > 0) and { "env" } or {}
  vim.list_extend(cmd, unset)
  vim.list_extend(cmd, set)
  vim.list_extend(cmd, self.tool.cmd)
  return table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
end

---@param pane_id string
function M.process_info(pane_id)
  local ret = M.api({ "pane", "process-info", "--pane", pane_id }, { notify = false })
  return ret and ret.process_info
end

function M:is_running()
  return self.herdr_pid and vim.api.nvim_get_proc(self.herdr_pid) ~= nil
end

function M.sessions()
  local ret = {} ---@type sidekick.cli.session.State[]
  local list = M.api({ "pane", "list" }, { notify = false })
  if not list then
    return ret
  end
  local tools = Config.tools()

  local Procs = require("sidekick.cli.procs")
  local procs = Procs.new()
  for _, pane in ipairs(list.panes or {}) do
    local info = M.process_info(pane.pane_id)
    local pid = info and info.shell_pid
    if pid then
      procs:walk(pid, function(proc)
        for _, tool in pairs(tools) do
          if tool:is_proc(proc) then
            ret[#ret + 1] = {
              id = ("herdr %d"):format(pid),
              cwd = proc.cwd or pane.foreground_cwd or pane.cwd,
              tool = tool,
              herdr_pane_id = pane.pane_id,
              herdr_pid = pid,
              mux_session = pane.pane_id,
              pids = Procs.pids(pid),
            }
            return true
          end
        end
      end)
    end
  end

  return ret
end

---Send text to a herdr pane
function M:send(text)
  local function send()
    Util.exec({ "herdr", "pane", "send-text", self.herdr_pane_id, text })
  end

  if self.tool.mux_focus then
    -- Send focus-in event first (some TUI apps like qwen ignore input when unfocused)
    Util.exec({ "herdr", "pane", "send-text", self.herdr_pane_id, "\27[I" })
    vim.defer_fn(send, 50) -- slight delay to ensure focus event is processed first
  else
    send()
  end
end

function M:submit()
  Util.exec({ "herdr", "pane", "send-keys", self.herdr_pane_id, "enter" })
end

function M:dump()
  if not self.herdr_pane_id then
    return
  end
  local _, ret = Util.exec({
    "herdr",
    "pane",
    "read",
    self.herdr_pane_id,
    "--source",
    "recent",
    "--lines",
    tostring(Config.cli.mux.dump),
    "--format",
    "ansi",
  })
  return ret and (ret:gsub("\r\n", "\n")) or nil
end

return M
