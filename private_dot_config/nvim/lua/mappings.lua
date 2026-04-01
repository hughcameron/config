require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })

map("i", "jk", "<ESC>")

map("n", "<leader>ws", "<cmd>Telescope keymaps<cr>", { desc = "Search keymaps" })
map("n", "<leader>fc", "<cmd>Telescope commands<cr>", { desc = "Command palette" })

map("n", "<leader>fd", function()
  require("telescope.builtin").find_files({
    find_command = { "fd", "--type", "d", "--hidden", "--exclude", ".git" },
    prompt_title = "Find Directories",
  })
end, { desc = "Find directories" })

-- Window navigation from terminal mode (bypass zsh keybindings)
map("t", "<C-h>", "<C-\\><C-N><C-w>h", { desc = "switch window left" })
map("t", "<C-l>", "<C-\\><C-N><C-w>l", { desc = "switch window right" })
map("t", "<C-j>", "<C-\\><C-N><C-w>j", { desc = "switch window down" })
map("t", "<C-k>", "<C-\\><C-N><C-w>k", { desc = "switch window up" })


-- LSP symbol navigation
map("n", "<leader>ls", "<cmd>Telescope lsp_document_symbols<cr>", { desc = "LSP document symbols" })
map("n", "<leader>lS", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", { desc = "LSP workspace symbols" })

-- Free Ctrl+N from NvChad's nvim-tree toggle (already on <leader>e)
vim.keymap.del("n", "<C-n>")

-- Markdown
map("n", "<leader>mr", "<cmd>RenderMarkdown toggle<cr>", { desc = "Toggle markdown render" })

-- Line navigation
map({"n", "v"}, "gh", "^", { desc = "Go to first non-blank character" })
map({"n", "v"}, "gl", "$", { desc = "Go to end of line" })

-- Quit / Save / Close
map("n", "<leader>qq", "<cmd>wqa<cr>", { desc = "Save and quit Neovim" })
map("n", "<leader>qw", "<cmd>w<cr>", { desc = "Save buffer" })
map("n", "<leader>qx", "<cmd>bd!<cr>", { desc = "Close buffer without saving" })
