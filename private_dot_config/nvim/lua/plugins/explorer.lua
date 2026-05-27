return {
  "folke/snacks.nvim",
  opts = {
    -- Inside tmux, snacks.image's terminal capability probe response
    -- leaks into the picker prompt as keystrokes (tmux extended-keys
    -- swallows TermResponse). Upstream-confirmed; tmux wontfix.
    -- See folke/snacks.nvim#2332.
    image = { enabled = vim.env.TMUX == nil },
    picker = {
      sources = {
        explorer = {
          hidden = true,
        },
        files = {
          hidden = true,
          exclude = { ".git" },
        },
      },
    },
  },
}
