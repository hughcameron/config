return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    opts = require "configs.conform",
  },

  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "vim", "lua", "vimdoc",
        "html", "css", "json", "yaml", "toml",
        "python", "bash", "markdown", "sql",
        "javascript", "typescript",
      },
    },
  },

  -- Fix gitsigns auto-attach (User FilePost fires too early)
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPost", "BufNewFile" },
  },

  -- Git integration — lazygit in a floating terminal
  {
    "kdheepak/lazygit.nvim",
    lazy = true,
    cmd = {
      "LazyGit",
      "LazyGitConfig",
      "LazyGitCurrentFile",
      "LazyGitFilter",
      "LazyGitFilterCurrentFile",
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    keys = {
      { "<leader>gg", "<cmd>LazyGit<cr>", desc = "LazyGit" },
    },
  },

  -- Git diffview
  {
    "sindrets/diffview.nvim",
    lazy = true,
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview Open" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File History" },
    },
  },

  -- File browser — Yazi in a floating terminal (Miller Columns)
  {
    "mikavilpas/yazi.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>y", "<cmd>Yazi<cr>", desc = "Yazi (current file)" },
      { "<leader>Y", "<cmd>Yazi cwd<cr>", desc = "Yazi (cwd)" },
    },
    opts = {
      open_for_directories = true,
    },
  },

  -- Jump to any word on screen
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
    },
    opts = {},
  },

  -- Markdown rendering inline
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {},
  },

  -- GitHub PRs and issues inside nvim
  {
    "pwntester/octo.nvim",
    cmd = "Octo",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {},
    keys = {
      { "<leader>go", "<cmd>Octo pr list<cr>", desc = "Octo: list PRs" },
    },
  },

  -- Which-key group labels
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>m", group = "Bookmarks" },
        { "<leader>g", group = "Git" },
      },
    },
  },

  -- Vim motion practice
  {
    "ThePrimeagen/vim-be-good",
    cmd = "VimBeGood",
  },

  -- File management — edit filesystem like a buffer
  {
    "stevearc/oil.nvim",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      default_file_explorer = true,
      view_options = {
        show_hidden = true,
      },
    },
    keys = {
      { "-", "<cmd>Oil<cr>", desc = "Open parent directory (Oil)" },
    },
  },
}
