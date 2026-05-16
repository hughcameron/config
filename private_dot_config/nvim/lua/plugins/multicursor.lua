return {
  "jake-stewart/multicursor.nvim",
  branch = "1.0",
  event = "VeryLazy",
  config = function()
    local mc = require("multicursor-nvim")
    mc.setup()

    local set = vim.keymap.set

    -- Add cursor on word/selection and jump to next match (vim-visual-multi muscle memory)
    set({ "n", "x" }, "<C-n>", function() mc.matchAddCursor(1) end, { desc = "MC: add cursor at next match" })
    set({ "n", "x" }, "<C-S-n>", function() mc.matchAddCursor(-1) end, { desc = "MC: add cursor at prev match" })
    set({ "n", "x" }, "<C-x>", function() mc.matchSkipCursor(1) end, { desc = "MC: skip current match" })

    -- Add/remove cursor under mouse
    set("n", "<C-LeftMouse>", mc.handleMouse, { desc = "MC: toggle cursor at mouse" })

    -- Add cursor above/below current line
    set({ "n", "x" }, "<M-Up>", function() mc.lineAddCursor(-1) end, { desc = "MC: add cursor above" })
    set({ "n", "x" }, "<M-Down>", function() mc.lineAddCursor(1) end, { desc = "MC: add cursor below" })

    -- Select all matches of word/selection
    set({ "n", "x" }, "<leader>A", mc.matchAllAddCursors, { desc = "MC: add cursor at all matches" })

    -- <Esc>: re-enable cursors if disabled, else clear, else fall through
    set("n", "<esc>", function()
      if not mc.cursorsEnabled() then
        mc.enableCursors()
      elseif mc.hasCursors() then
        mc.clearCursors()
      else
        vim.cmd("nohlsearch")
      end
    end)

    -- Visual hint for non-main cursors so they're easier to spot
    local hl = vim.api.nvim_set_hl
    hl(0, "MultiCursorCursor", { link = "Cursor" })
    hl(0, "MultiCursorVisual", { link = "Visual" })
  end,
}
