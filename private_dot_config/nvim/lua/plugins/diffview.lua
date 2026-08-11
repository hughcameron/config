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

    -- Horizontal scroll is a *window* property, and diffview swaps new
    -- buffers into the same two windows on every step, so `leftcol` snaps
    -- back to 0 each time — you lose your place in a wide table on every
    -- j/k. Remember the last scroll position and restore it as each new
    -- diff buffer lands. `col` rides along because Vim clamps `leftcol` to
    -- keep the cursor on screen, so restoring one without the other is a
    -- no-op.
    local scroll = { leftcol = 0, col = 0 }

    vim.api.nvim_create_autocmd("WinScrolled", {
      group = vim.api.nvim_create_augroup("hc_diffview_scroll", { clear = true }),
      callback = function()
        local win = vim.api.nvim_get_current_win()
        local tagged, is_pane = pcall(vim.api.nvim_win_get_var, win, "hc_diffview_pane")
        if tagged and is_pane then
          local v = vim.fn.winsaveview()
          scroll.leftcol, scroll.col = v.leftcol, v.col
        end
      end,
    })

    -- A commit header across the top of the split. 'winbar' is per-window,
    -- so this is two halves that read as one banner: identity on the left
    -- pane, subject on the right. (A single spanning header would mean
    -- hijacking the global tabline, which bufferline already owns.)
    local function set_commit_winbar(winid, ctx)
      local ok, lib = pcall(require, "diffview.lib")
      if not ok then return end
      local view = lib.get_current_view()
      local commit = view and view.cur_entry and view.cur_entry.commit
      if not commit then return end -- e.g. the working-tree entry; keep diffview's

      -- Commit subjects are arbitrary text; a stray `%` is a winbar format item.
      local function esc(s)
        return (tostring(s or ""):gsub("%%", "%%%%"))
      end

      local bar
      if ctx and ctx.symbol == "a" then
        bar = table.concat({
          "%#Comment# before  %*",
          "%#Identifier#" .. esc(commit.hash:sub(1, 8)) .. "%*",
          "  %#Comment#" .. esc(commit.author) .. "  ·  " .. esc(commit.rel_date) .. "%*",
        })
      else
        bar = "%#Comment# after   %*" .. esc(commit.subject)
      end

      vim.wo[winid].winbar = bar
    end

    return {
      -- Upstream defaults already give `--follow` across renames; only the
      -- highlighting and the geometry below need changing.
      enhanced_diff_hl = true,
      view = {
        -- Three columns: old | new | commit history. diffview can't do a
        -- genuinely *inline* diff — file_history_view offers only
        -- diff2_horizontal and diff2_vertical (diff1_plain is merge_tool
        -- only), because nvim's diff mode is inherently two-window. For a
        -- real inline diff, see `<leader>gf`.
        --
        -- winbar_info labels each pane with the revision it holds, so old
        -- (left) and new (right) are told apart at a glance.
        file_history = { layout = "diff2_horizontal", winbar_info = true },
      },
      hooks = {
        -- Fires after diffview has displayed the buffer and set its own
        -- winbar, with `winid` current — so anything set here wins, and a
        -- failure here just leaves diffview's stock winbar in place.
        diff_buf_win_enter = function(_, winid, ctx)
          -- diffview opens diff buffers with foldmethod=diff / foldlevel=0
          -- (vcs/file.lua), so every unchanged region collapses and the file
          -- reads as fragments around the hunks. Turn folding off to render
          -- the whole file in both panes; `zi` toggles it back per window.
          vim.wo[winid].foldenable = false
          pcall(vim.api.nvim_win_set_var, winid, "hc_diffview_pane", true)

          -- Vim clamps `leftcol` to keep the cursor on screen, so on a line
          -- shorter than the scroll offset the view snaps back to column 0.
          -- These buffers are read-only history, so 'virtualedit' costs
          -- nothing and lets the cursor sit past end-of-line instead.
          vim.wo[winid].virtualedit = "all"

          if scroll.leftcol > 0 then
            -- Deferred: diffview repositions the cursor *after* this hook
            -- returns, which resets the view. Restoring inline measures as
            -- applied and is then silently undone.
            vim.schedule(function()
              if not vim.api.nvim_win_is_valid(winid) then return end
              vim.api.nvim_win_call(winid, function()
                vim.fn.winrestview({
                  leftcol = scroll.leftcol,
                  col = math.max(scroll.col, scroll.leftcol),
                })
              end)
            end)
          end

          set_commit_winbar(winid, ctx)
        end,
      },
      -- Commit list as the third column, on the right of the two diff panes.
      file_history_panel = {
        win_config = { position = "right", width = 50 },
      },
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
