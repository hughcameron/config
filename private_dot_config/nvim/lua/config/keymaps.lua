-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader><Tab>t", "<cmd>tab term<cr>", { desc = "New tab: terminal" })

-- :terminal doesn't pass CSI u, so Shift+Enter looks like plain Enter to the
-- child process. Send `\<CR>` instead — Claude Code (and most REPLs) treat
-- backslash+Enter as a line continuation.
vim.keymap.set("t", "<S-CR>", [[\<CR>]], { desc = "Terminal: insert newline (\\ + CR)" })
