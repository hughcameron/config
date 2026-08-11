-- Inline (unified) diff view of a file's history, as a counterpart to the
-- side-by-side one in diffview.lua.
--
-- LazyVim already binds `<leader>gf` to snacks' `git_log_file` picker, whose
-- preview runs `git show <commit> -- <file>` — a real unified diff, scoped to
-- the file. All that's missing is the geometry: the stock layout puts the
-- commit list left and the preview right. This flips it.
--
-- `j`/`k` in the list step commits and the diff follows automatically — the
-- picker previews on cursor move, so no remap is needed here (unlike
-- diffview's panel, see diffview.lua).

return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        git_log_file = {
          layout = {
            -- Supplying a full box spec (with `layout[1]` set) makes snacks
            -- skip preset resolution entirely, so this replaces the default
            -- geometry rather than array-merging into it.
            layout = {
              box = "horizontal",
              width = 0.92,
              height = 0.9,
              -- Diff on the left, taking the larger share.
              { win = "preview", title = "{preview}", border = true, width = 0.62 },
              -- Commit history on the right.
              {
                box = "vertical",
                border = true,
                title = "{title} {live} {flags}",
                { win = "input", height = 1, border = "bottom" },
                { win = "list", border = "none" },
              },
            },
          },
        },
      },
    },
  },
}
