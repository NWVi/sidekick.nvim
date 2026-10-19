---@module 'luassert'

local Config = require("sidekick.config")
local Herdr = require("sidekick.cli.session.herdr")

describe("herdr shell_cmd", function()
  local cases = {
    { cmd = { "claude" }, env = nil, expected = "'claude'" },
    { cmd = { "codex", "--foo bar" }, env = {}, expected = "'codex' '--foo bar'" },
    { cmd = { "cat" }, env = { FOO = false }, expected = "'env' '-u' 'FOO' 'cat'" },
    { cmd = { "cat" }, env = { BAR = "x y" }, expected = "'env' 'BAR=x y' 'cat'" },
    -- unsets must always come before assignments
    { cmd = { "cat" }, env = { BAR = "x y", FOO = false }, expected = "'env' '-u' 'FOO' 'BAR=x y' 'cat'" },
  }

  for _, case in ipairs(cases) do
    it(case.expected, function()
      local session = setmetatable({ tool = { cmd = case.cmd, env = case.env } }, Herdr)
      assert.are.same(case.expected, session:shell_cmd())
    end)
  end
end)

describe("herdr split_ratio", function()
  local size

  before_each(function()
    size = Config.cli.mux.split.size
  end)

  after_each(function()
    Config.cli.mux.split.size = size
  end)

  -- herdr's ratio is the share kept by the current pane
  for _, case in ipairs({ { 0.5, 0.5 }, { 0.3, 0.7 }, { 1, 0 } }) do
    it(("size %s -> ratio %s"):format(case[1], case[2]), function()
      Config.cli.mux.split.size = case[1]
      assert.is_true(math.abs(Herdr.split_ratio({}) - case[2]) < 1e-9)
    end)
  end
end)
