local M = {}
local config = {}
local bookmarks = {}

-- ── Persistence ──────────────────────────────────────────────

local function data_path()
  return config.path or (vim.fn.stdpath("data") .. "/dir-bookmarks.json")
end

local function load()
  local p = data_path()
  if vim.fn.filereadable(p) == 0 then return end
  local raw = table.concat(vim.fn.readfile(p), "\n")
  local ok, decoded = pcall(vim.fn.json_decode, raw)
  if ok and type(decoded) == "table" then bookmarks = decoded end
end

local function save()
  local p = data_path()
  vim.fn.mkdir(vim.fn.fnamemodify(p, ":h"), "p")
  vim.fn.writefile({ vim.fn.json_encode(bookmarks) }, p)
end

-- ── Core operations ──────────────────────────────────────────

function M.add(letter, path, label)
  path = vim.fn.fnamemodify(path or vim.fn.getcwd(), ":p"):gsub("/$", "")
  bookmarks[letter] = { path = path, label = label or "", created = os.time() }
  save()
  vim.notify(("[%s] %s -> %s"):format(letter, label or "", path), vim.log.levels.INFO)
end

function M.jump(letter)
  local bm = bookmarks[letter]
  if not bm then
    vim.notify("No bookmark: " .. letter, vim.log.levels.WARN)
    return
  end
  if vim.fn.isdirectory(bm.path) == 1 then
    vim.cmd.cd(bm.path)
    vim.notify(("cd -> [%s] %s"):format(letter, bm.path), vim.log.levels.INFO)
  else
    vim.cmd.edit(bm.path)
  end
end

function M.delete(letter)
  if not bookmarks[letter] then
    vim.notify("No bookmark: " .. letter, vim.log.levels.WARN)
    return
  end
  local path = bookmarks[letter].path
  bookmarks[letter] = nil
  save()
  vim.notify(("Deleted [%s] -> %s"):format(letter, path), vim.log.levels.INFO)
end

function M.rename(old_letter, new_letter)
  if not bookmarks[old_letter] then
    vim.notify("No bookmark: " .. old_letter, vim.log.levels.WARN)
    return
  end
  if bookmarks[new_letter] then
    vim.notify(("[%s] already exists"):format(new_letter), vim.log.levels.ERROR)
    return
  end
  bookmarks[new_letter] = bookmarks[old_letter]
  bookmarks[old_letter] = nil
  save()
  vim.notify(("Renamed [%s] -> [%s]"):format(old_letter, new_letter), vim.log.levels.INFO)
end

function M.clear_all()
  bookmarks = {}
  save()
  vim.notify("All bookmarks cleared", vim.log.levels.INFO)
end

function M.list_all()
  local result = {}
  for letter, data in pairs(bookmarks) do
    table.insert(result, vim.tbl_extend("force", { letter = letter }, data))
  end
  table.sort(result, function(a, b) return a.letter < b.letter end)
  return result
end

-- ── Floating window (jump) ───────────────────────────────────

function M.open_float()
  local items = M.list_all()
  if #items == 0 then
    vim.notify("No bookmarks — add one with " .. config.leader .. "a", vim.log.levels.WARN)
    return
  end

  -- Build display lines
  local lines = {}
  local max_label = 0
  for _, bm in ipairs(items) do
    local label = bm.label ~= "" and bm.label or vim.fn.fnamemodify(bm.path, ":t")
    if #label > max_label then max_label = #label end
  end
  for _, bm in ipairs(items) do
    local label = bm.label ~= "" and bm.label or vim.fn.fnamemodify(bm.path, ":t")
    local short_path = vim.fn.fnamemodify(bm.path, ":~")
    table.insert(lines, ("  [%s]  %-" .. max_label .. "s  %s"):format(bm.letter, label, short_path))
  end
  table.insert(lines, "")
  table.insert(lines, "  Press letter to jump, q to close")

  -- Calculate window size
  local width = 0
  for _, line in ipairs(lines) do
    if #line > width then width = #line end
  end
  width = width + 4
  local height = #lines

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Bookmarks ",
    title_pos = "center",
  })

  -- Close on q or Escape
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })

  -- Map each bookmark letter to jump
  for _, bm in ipairs(items) do
    local letter = bm.letter
    vim.keymap.set("n", letter, function()
      close()
      M.jump(letter)
    end, { buffer = buf, nowait = true })
  end
end

-- ── Interactive add ──────────────────────────────────────────

function M.add_interactive()
  local default_label = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  vim.ui.input({ prompt = "Label: ", default = default_label }, function(label)
    if not label then return end
    vim.ui.input({ prompt = "Bookmark letter: " }, function(letter)
      if not letter or letter == "" then return end
      letter = letter:sub(1, 1):lower()
      if bookmarks[letter] then
        local msg = ("[%s] exists -> %s. Overwrite? (y/n): "):format(letter, bookmarks[letter].path)
        vim.ui.input({ prompt = msg }, function(confirm)
          if confirm ~= "y" then return end
          M.add(letter, nil, label ~= "" and label or nil)
        end)
      else
        M.add(letter, nil, label ~= "" and label or nil)
      end
    end)
  end)
end

-- ── Telescope pickers (CRUD) ─────────────────────────────────

local function make_telescope_picker(opts)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    vim.notify("Telescope not available", vim.log.levels.ERROR)
    return
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local items = M.list_all()
  if #items == 0 then
    vim.notify("No bookmarks", vim.log.levels.WARN)
    return
  end

  pickers.new({}, {
    prompt_title = opts.title or "Bookmarks",
    finder = finders.new_table({
      results = items,
      entry_maker = function(entry)
        local label = entry.label ~= "" and entry.label or vim.fn.fnamemodify(entry.path, ":t")
        local display = ("[%s]  %s  %s"):format(
          entry.letter, label, vim.fn.fnamemodify(entry.path, ":~")
        )
        return {
          value = entry,
          display = display,
          ordinal = entry.letter .. " " .. (entry.label or "") .. " " .. entry.path,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local sel = action_state.get_selected_entry()
        if sel then opts.on_select(sel.value) end
      end)
      return true
    end,
  }):find()
end

function M.telescope_delete()
  make_telescope_picker({
    title = "Delete Bookmark",
    on_select = function(bm) M.delete(bm.letter) end,
  })
end

function M.telescope_rename()
  make_telescope_picker({
    title = "Rename Bookmark",
    on_select = function(bm)
      vim.ui.input({ prompt = ("New letter for [%s]: "):format(bm.letter) }, function(new)
        if new and #new >= 1 then M.rename(bm.letter, new:sub(1, 1):lower()) end
      end)
    end,
  })
end

-- ── Setup ────────────────────────────────────────────────────

function M.setup(opts)
  config = vim.tbl_deep_extend("force", {
    path = vim.fn.stdpath("data") .. "/dir-bookmarks.json",
    leader = "<leader>b",
  }, opts or {})

  load()

  local leader = config.leader
  local map = vim.keymap.set
  map("n", leader .. "g", M.open_float,       { desc = "Bookmark: jump (float)" })
  map("n", leader .. "a", M.add_interactive,   { desc = "Bookmark: add" })
  map("n", leader .. "d", M.telescope_delete,  { desc = "Bookmark: delete" })
  map("n", leader .. "r", M.telescope_rename,  { desc = "Bookmark: rename" })
  map("n", leader .. "A", M.clear_all,         { desc = "Bookmark: clear all" })
  map("n", leader .. "l", function()
    local bms = M.list_all()
    if #bms == 0 then vim.notify("No bookmarks", vim.log.levels.WARN); return end
    local lines = {}
    for _, bm in ipairs(bms) do
      local label = bm.label ~= "" and bm.label or ""
      table.insert(lines, ("[%s]  %s  %s"):format(
        bm.letter, label, vim.fn.fnamemodify(bm.path, ":~")
      ))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "Bookmark: list all" })
end

return M
