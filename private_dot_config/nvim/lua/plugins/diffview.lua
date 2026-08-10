-- Step through every historical diff of a single file: commit list on the
-- left, side-by-side diff of that commit on the right, `j`/`k` to walk.
--
-- Keys sit under `<leader>gv` because LazyVim already owns `<leader>gf`
-- (snacks git_log_file), and `<leader>gd`/`<leader>gc` get claimed the moment
-- the fzf or telescope extra is enabled.
--
-- Diffview infers the repo from the current buffer rather than from cwd, so
-- these work on a file in a different repo than the one nvim started in.

return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles" },
  keys = {
    { "<leader>gv", "", desc = "+diffview" },
    { "<leader>gvf", "<cmd>DiffviewFileHistory %<cr>", desc = "File History (current file)" },
    -- Visual mode: traces the evolution of just the selected lines (git log -L).
    { "<leader>gvf", ":DiffviewFileHistory<cr>", mode = "x", desc = "File History (selected lines)" },
    { "<leader>gvF", "<cmd>DiffviewFileHistory<cr>", desc = "File History (repo)" },
    { "<leader>gvo", "<cmd>DiffviewOpen<cr>", desc = "Open (working tree diff)" },
    { "<leader>gvq", "<cmd>DiffviewClose<cr>", desc = "Close" },
  },
  -- Upstream defaults already give the side-by-side `diff2_horizontal` layout
  -- and `--follow` across renames; only the highlighting needs turning up.
  opts = { enhanced_diff_hl = true },
}
