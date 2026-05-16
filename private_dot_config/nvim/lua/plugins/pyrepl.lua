return {
  "dangooddd/pyrepl.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  cmd = {
    "PyreplOpen", "PyreplClose", "PyreplHide", "PyreplToggle",
    "PyreplToggleFocus", "PyreplSendVisual", "PyreplSendBuffer",
    "PyreplSendCell", "PyreplStepCellForward", "PyreplStepCellBackward",
    "PyreplOpenImageHistory", "PyreplExport", "PyreplConvert", "PyreplInstall",
  },
  keys = {
    { "<leader>jo", function() require("pyrepl").open_repl() end, desc = "Pyrepl: open" },
    { "<leader>jh", function() require("pyrepl").hide_repl() end, desc = "Pyrepl: hide" },
    { "<leader>jc", function() require("pyrepl").close_repl() end, desc = "Pyrepl: close" },
    { "<leader>jt", function() require("pyrepl").toggle_repl() end, desc = "Pyrepl: toggle" },
    { "<leader>ji", function() require("pyrepl").open_image_history() end, desc = "Pyrepl: image history" },
    { "<leader>jf", function() require("pyrepl").toggle_repl_focus() end, mode = { "n", "t" }, desc = "Pyrepl: toggle focus" },
    { "<leader>jb", function() require("pyrepl").send_buffer() end, desc = "Pyrepl: send buffer" },
    { "<leader>jl", function() require("pyrepl").send_cell() end, desc = "Pyrepl: send cell" },
    { "<leader>jv", function() require("pyrepl").send_visual() end, mode = "v", desc = "Pyrepl: send visual" },
    { "<leader>jp", function() require("pyrepl").step_cell_backward() end, desc = "Pyrepl: prev cell" },
    { "<leader>jn", function() require("pyrepl").step_cell_forward() end, desc = "Pyrepl: next cell" },
    { "<leader>je", function() require("pyrepl").export_to_notebook() end, desc = "Pyrepl: export to notebook" },
  },
  opts = {
    split_horizontal = false,
    split_ratio = 0.5,
    style = "default",
    style_integration = true,
    image_max_history = 10,
    image_width_ratio = 0.5,
    image_height_ratio = 0.5,
    image_provider = "placeholders",
    cell_pattern = "^# %%%%.*$",
    python_path = "python",
    preferred_kernel = "python3",
    jupytext_hook = true,
  },
  config = function(_, opts)
    require("pyrepl").setup(opts)

    -- Override pyrepl's cached python resolver so it honors $VIRTUAL_ENV
    -- (set by venv-selector.nvim) at every REPL open, not just the first.
    local python_mod = require("pyrepl.python")
    python_mod.get_python_path = function()
      local venv = vim.env.VIRTUAL_ENV
      if venv and vim.fn.executable(venv .. "/bin/python") == 1 then
        return venv .. "/bin/python"
      end
      for _, candidate in ipairs({ "python", "python3" }) do
        if vim.fn.executable(candidate) == 1 then
          return vim.fn.exepath(candidate)
        end
      end
      error("pyrepl: python executable not found; activate a venv via <leader>cv")
    end
  end,
}
