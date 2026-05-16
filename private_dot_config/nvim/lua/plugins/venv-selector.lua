return {
  "linux-cultist/venv-selector.nvim",
  ft = "python",
  cmd = { "VenvSelect", "VenvSelectCached", "VenvSelectLog" },
  keys = {
    { "<leader>cv", "<cmd>VenvSelect<cr>", desc = "Select venv" },
  },
  opts = {
    options = {
      picker = "snacks",
      notify_user_on_venv_activation = true,
      cached_venv_automatic_activation = true,
    },
    search = {},
  },
}
