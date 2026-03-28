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
      keymaps = {
        change_working_directory = "<c-s>",
      },
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

  -- Multi-cursor (Ctrl+N to select next match, plugin defaults)
  {
    "mg979/vim-visual-multi",
    lazy = false,
    init = function()
      vim.g.VM_theme = "neon"
    end,
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
      { "<leader>go", "<cmd>Octo pr list<cr>", desc = "Octo: list PRs (open)" },
      { "<leader>gm", "<cmd>Octo pr list states=MERGED<cr>", desc = "Octo: list PRs (merged)" },
      { "<leader>gc", "<cmd>Octo pr list states=CLOSED<cr>", desc = "Octo: list PRs (closed)" },
    },
  },

  -- Which-key group labels
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>g", group = "Git" },
        { "<leader>q", group = "Quit/Save" },
        { "<leader>m", group = "Minimap / Markdown" },
      },
    },
  },

  -- Nvim-tree: side panel with flash.nvim support
  {
    "nvim-tree/nvim-tree.lua",
    opts = {
      on_attach = function(bufnr)
        local api = require("nvim-tree.api")
        api.config.mappings.default_on_attach(bufnr)
        vim.keymap.del("n", "s", { buffer = bufnr })
      end,
      view = {
        width = 35,
      },
    },
  },

  -- Minimap — braille-encoded buffer overview
  {
    "echasnovski/mini.map",
    event = "VeryLazy",
    keys = {
      { "<leader>mm", function() require("mini.map").toggle() end, desc = "Toggle minimap" },
    },
    opts = function()
      local map = require("mini.map")
      return {
        symbols = {
          encode = map.gen_encode_symbols.shade("1x1"),
        },
        integrations = {
          map.gen_integration.builtin_search(),
          map.gen_integration.gitsigns(),
          map.gen_integration.diagnostic(),
        },
        window = {
          width = 10,
          winblend = 50,
        },
      }
    end,
    config = function(_, opts)
      local map = require("mini.map")
      map.setup(opts)
      map.open()
    end,
  },

  -- Vim motion practice
  {
    "ThePrimeagen/vim-be-good",
    cmd = "VimBeGood",
  },


  -- Suggest better motions (hint mode — doesn't block input)
  {
    "m4xshen/hardtime.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      restriction_mode = "hint",
      restricted_keys = {
        ["<C-N>"] = {},  -- free for vim-visual-multi
      },
    },
  },

  -- Show available motions as virtual text
  {
    "tris203/precognition.nvim",
    event = "VeryLazy",
    opts = {},
  },

}
