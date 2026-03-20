require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

map("n", "<leader>ws", "<cmd>Telescope keymaps<cr>", { desc = "Search keymaps" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
