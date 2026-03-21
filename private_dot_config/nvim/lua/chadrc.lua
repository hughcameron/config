-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "nightowl",

  hl_override = {
    Comment = { italic = true },
    ["@comment"] = { italic = true },
  },
}

M.ui = {
  statusline = {
    modules = {
      git = function()
        local bufnr = vim.api.nvim_win_get_buf(vim.g.statusline_winid or 0)
        local git_status = vim.b[bufnr].gitsigns_status_dict

        if git_status then
          local added = (git_status.added and git_status.added ~= 0) and ("  " .. git_status.added) or ""
          local changed = (git_status.changed and git_status.changed ~= 0) and ("  " .. git_status.changed) or ""
          local removed = (git_status.removed and git_status.removed ~= 0) and ("  " .. git_status.removed) or ""
          return "%#St_gitIcons#  " .. git_status.head .. added .. changed .. removed
        end

        -- Fallback: show branch from cwd even for non-git buffers
        local head = vim.fn.system("git -C " .. vim.fn.getcwd() .. " branch --show-current 2>/dev/null"):gsub("\n", "")
        if head ~= "" then
          return "%#St_gitIcons#  " .. head
        end

        return ""
      end,
    },
  },
}

M.nvdash = { load_on_startup = true }

return M
