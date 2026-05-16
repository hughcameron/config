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
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "night-owl",
    },
  },
}
