-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- LazyVim clears clipboard over SSH expecting nvim's built-in OSC 52
-- provider to kick in, but tmux is detected first and wins. Force
-- unnamedplus so yanks reach the + register; tmux's set-clipboard
-- forwards OSC 52 through Ghostty to the macOS clipboard.
vim.opt.clipboard = "unnamedplus"
