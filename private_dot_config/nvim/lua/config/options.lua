-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Over SSH, force nvim's built-in OSC 52 provider. Auto-detection
-- prefers tmux but doesn't reliably wire up at runtime under LazyVim's
-- lazy clipboard restore. OSC 52 writes escape sequences direct to
-- stdout; tmux (allow-passthrough on) forwards them and Ghostty
-- writes to the macOS clipboard.
if vim.env.SSH_CONNECTION then
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
      ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
      ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
      ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
    },
  }
end
vim.opt.clipboard = "unnamedplus"
