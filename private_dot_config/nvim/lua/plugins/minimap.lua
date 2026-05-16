return {
  "gorbit99/codewindow.nvim",
  event = "VeryLazy",
  keys = {
    { "<leader>mm", desc = "Minimap: toggle focus" },
    { "<leader>mo", desc = "Minimap: open" },
    { "<leader>mc", desc = "Minimap: close" },
    { "<leader>mf", desc = "Minimap: focus" },
  },
  config = function()
    local cw = require("codewindow")
    cw.setup({
      auto_enable = false,
      window_border = "single",
      exclude_filetypes = { "snacks_dashboard", "neo-tree", "lazy", "mason", "help" },
    })
    cw.apply_default_keybinds()
  end,
}
