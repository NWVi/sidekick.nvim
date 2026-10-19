---@module 'luassert'

local Config = require("sidekick.config")
local Herdr = require("sidekick.cli.session.herdr")
local Session = require("sidekick.cli.session")

Session.register("herdr", Herdr)

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

describe("mux registry", function()
  local Mux = require("sidekick.cli.session.mux")
  local env

  before_each(function()
    env = { ZELLIJ = vim.env.ZELLIJ, HERDR_ENV = vim.env.HERDR_ENV, TMUX = vim.env.TMUX }
    vim.env.ZELLIJ, vim.env.HERDR_ENV, vim.env.TMUX = nil, nil, nil
  end)

  after_each(function()
    for k, v in pairs(env) do
      vim.env[k] = v
    end
  end)

  local cases = {
    { {}, "tmux" },
    { { TMUX = "1" }, "tmux" },
    { { HERDR_ENV = "1" }, "herdr" },
    { { HERDR_ENV = "1", TMUX = "1" }, "herdr" },
    { { ZELLIJ = "0", HERDR_ENV = "1" }, "zellij" },
  }
  for _, case in ipairs(cases) do
    it(("detect %s -> %s"):format(vim.inspect(case[1]), case[2]), function()
      for k, v in pairs(case[1]) do
        vim.env[k] = v
      end
      assert.are.same(case[2], Mux.detect())
    end)
  end
end)

describe("session create_mode", function()
  local create

  before_each(function()
    create = Config.cli.mux.create
  end)

  after_each(function()
    Config.cli.mux.create = create
  end)

  local cases = {
    { "split", "split" },
    { "window", "window" },
    -- unsupported modes fall back to the first supported one
    { "terminal", "split" },
  }
  for _, case in ipairs(cases) do
    it(("herdr %s -> %s"):format(case[1], case[2]), function()
      Config.cli.mux.create = case[1]
      local session = setmetatable({ backend = "herdr" }, Herdr)
      assert.are.same(case[2], session:create_mode())
    end)
  end
end)
