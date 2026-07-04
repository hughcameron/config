return {
  "folke/snacks.nvim",
  opts = {
    -- Safe in tmux only while extended-keys is "on" (not "always"): snacks
    -- then skips its TermResponse probe and asks tmux for client_termname
    -- instead (folke/snacks.nvim#2332). "always" re-triggers the probe,
    -- which leaks into the picker prompt as keystrokes.
    image = { enabled = true },
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
