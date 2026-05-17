return {
  {
    "oxfist/night-owl.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      italics = true,
      bold = true,
      underline = true,
      undercurl = true,
      transparent_background = false,
    },
    init = function()
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "night-owl",
        callback = function()
          local hl = vim.api.nvim_set_hl
          hl(0, "DiffAdd", { fg = "#9ccc65", bg = "#13301a" })
          hl(0, "DiffChange", { fg = "#e2b93d", bg = "#33280d" })
          hl(0, "DiffDelete", { fg = "#ef5350", bg = "#3a1414" })
          hl(0, "DiffText", { fg = "#e2b93d", bg = "#5a4416", bold = true })
          hl(0, "@diff.plus", { link = "DiffAdd" })
          hl(0, "@diff.minus", { link = "DiffDelete" })
          hl(0, "@diff.delta", { link = "DiffChange" })
          hl(0, "Added", { fg = "#9ccc65" })
          hl(0, "Removed", { fg = "#ef5350" })
          hl(0, "Changed", { fg = "#e2b93d" })
        end,
      })
    end,
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "night-owl",
    },
  },
}
