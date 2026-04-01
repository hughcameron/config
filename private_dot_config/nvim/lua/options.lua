require "nvchad.options"

local o = vim.o

-- Match previous Helix preferences
o.relativenumber = true
o.mouse = ""
o.cursorlineopt = "both"

-- Allow cursor one past end of line in normal mode
o.virtualedit = "onemore"

-- Sensible defaults
o.scrolloff = 8
o.wrap = true
o.linebreak = true

-- Use OSC 52 for clipboard (works over SSH via Ghostty)
vim.g.clipboard = {
  name = "OSC 52",
  copy = {
    ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
    ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
  },
  paste = {
    ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
    ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
  },
}
