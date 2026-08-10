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
  -- `opts` is a function so `diffview.actions` is only required at config
  -- time — requiring it at the top of the file would defeat the lazy load.
  opts = function()
    local actions = require("diffview.actions")

    return {
      -- Upstream defaults already give the side-by-side `diff2_horizontal`
      -- layout and `--follow` across renames; only highlighting needs raising.
      enhanced_diff_hl = true,
      keymaps = {
        file_history_panel = {
          -- Out of the box `j`/`k` only move the cursor — you then have to
          -- press <cr> to load each diff, which is two keys per commit when
          -- walking a long history. `select_next_entry` moves *and* loads,
          -- and leaves focus in the panel, so j/k alone steps the history.
          -- <Down>/<Up> keep the stock move-without-loading behaviour.
          { "n", "j", actions.select_next_entry, { desc = "Next commit + load its diff" } },
          { "n", "k", actions.select_prev_entry, { desc = "Prev commit + load its diff" } },
        },
      },
    }
  end,
}
