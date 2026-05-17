return {
  "folke/which-key.nvim",
  opts = function(_, opts)
    local width = 60
    local height = 20
    opts.preset = false
    opts.win = vim.tbl_deep_extend("force", opts.win or {}, {
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      width = { min = width, max = width },
      height = { min = 4, max = height },
      border = "rounded",
      title = true,
      title_pos = "center",
    })
    return opts
  end,
}
