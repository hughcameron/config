return {
  "mg979/vim-visual-multi",
  branch = "master",
  event = "VeryLazy",
  init = function()
    vim.g.VM_maps = {
      ["Find Under"] = "<C-n>",
      ["Find Subword Under"] = "<C-n>",
      ["Select All"] = "<leader>A",
      ["Skip Region"] = "<C-x>",
      ["Add Cursor Up"] = "<M-Up>",
      ["Add Cursor Down"] = "<M-Down>",
    }
    vim.g.VM_set_statusline = 0
    vim.g.VM_silent_exit = 1

    -- VM writes yanks to the unnamed register directly via setreg(),
    -- bypassing clipboard=unnamedplus. Mirror " -> + on VM exit so
    -- multi-region yanks land in the system clipboard.
    vim.api.nvim_create_autocmd("User", {
      pattern = "visual_multi_exit",
      callback = function()
        vim.fn.setreg("+", vim.fn.getreg('"'), vim.fn.getregtype('"'))
      end,
    })
  end,
}
