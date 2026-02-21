--- GCS Browser: Browse Google Cloud Storage buckets and objects from yazi.
--- Uses gcloud storage ls + fzf for interactive navigation.
--- Keybinding: g s
--- Modeled on yazi's built-in fzf.lua plugin pattern.

local M = {}

local get_cwd = ya.sync(function()
	return cx.active.current.cwd
end)

--- Run a command and capture stdout, returning output string or nil + error.
--- @param cmd string  Command name
--- @param args table  Arguments
--- @return string?, string?  stdout, error
local function run_cmd(cmd, args)
	local child, err = Command(cmd):arg(args):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
	if not child then
		return nil, "Failed to start " .. cmd .. ": " .. tostring(err)
	end

	local output, wait_err = child:wait_with_output()
	if not output then
		return nil, "Failed to read output: " .. tostring(wait_err)
	end
	if not output.status.success then
		return nil, output.stderr ~= "" and output.stderr or ("exit code " .. tostring(output.status.code))
	end
	return output.stdout, nil
end

--- List GCS path contents via gcloud storage ls.
--- @param path string|nil  nil = list buckets, "gs://bucket/path/" = list contents
--- @return table|nil items, string|nil err
local function gcs_ls(path)
	local args = { "storage", "ls" }
	if path then
		args[#args + 1] = path
	end

	local stdout, err = run_cmd("gcloud", args)
	if not stdout then
		return nil, err
	end

	local items = {}
	for line in stdout:gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if #line > 0 then
			items[#items + 1] = line
		end
	end

	if #items == 0 then
		return nil, "No items found"
	end
	return items
end

--- Strip the parent path prefix for cleaner fzf display.
--- @param item string  Full gs:// path
--- @param prefix string|nil  Parent path to strip
--- @return string
local function display_name(item, prefix)
	if not prefix then
		return item:match("^gs://(.+)$") or item
	end
	local name = item:sub(#prefix + 1)
	return #name > 0 and name or item
end

--- Run fzf with items piped via stdin. Follows built-in fzf.lua pattern:
--- spawn() + write_all() + wait_with_output()
--- @param items table  Full gs:// paths
--- @param current_path string|nil
--- @return table|nil  { action, path }
local function fzf_pick(items, current_path)
	local names = {}
	for _, item in ipairs(items) do
		names[#names + 1] = display_name(item, current_path)
	end

	local header = (current_path or "GCS Buckets")
		.. "\n"
		.. "Enter=open  Ctrl-Y=copy path  Ctrl-D=download  Esc=back"

	local child, spawn_err = Command("fzf")
		:arg({ "--no-sort", "--expect=ctrl-y,ctrl-d", "--prompt", "GCS > ", "--header", header })
		:stdin(Command.PIPED)
		:stdout(Command.PIPED)
		:spawn()

	if not child then
		ya.notify({ title = "GCS Browser", content = "fzf failed: " .. tostring(spawn_err), timeout = 5, level = "error" })
		return nil
	end

	-- Pipe items to fzf's stdin
	for _, name in ipairs(names) do
		child:write_all(name .. "\n")
	end
	child:flush()

	local output, wait_err = child:wait_with_output()
	if not output then
		return nil
	end
	-- fzf exit 130 = Esc/Ctrl-C (no selection) — not an error
	if not output.status.success and output.status.code ~= 130 then
		return nil
	end

	-- Parse: line 1 = key pressed (empty for Enter), line 2 = selected item
	local stdout = output.stdout or ""
	local key, selected = stdout:match("^(.-)\n(.-)%s*$")
	if not selected or #selected == 0 then
		return nil
	end

	for i, name in ipairs(names) do
		if name == selected then
			local action = "enter"
			if key == "ctrl-y" then
				action = "ctrl-y"
			elseif key == "ctrl-d" then
				action = "ctrl-d"
			end
			return { action = action, path = items[i] }
		end
	end
	return nil
end

--- Copy gs:// path to clipboard.
local function copy_path(path)
	ya.clipboard(path)
	ya.notify({ title = "GCS Browser", content = "Copied: " .. path, timeout = 3 })
end

--- Download a GCS object to local directory.
local function download(gs_path, cwd)
	ya.notify({ title = "GCS Browser", content = "Downloading...", timeout = 2 })

	local _, err = run_cmd("gcloud", { "storage", "cp", gs_path, tostring(cwd) .. "/" })
	if err then
		ya.notify({ title = "GCS Browser", content = "Download failed: " .. err, timeout = 5, level = "error" })
	else
		local filename = gs_path:match("([^/]+)$") or gs_path
		ya.notify({ title = "GCS Browser", content = "Downloaded: " .. filename, timeout = 3 })
	end
end

function M:entry()
	-- Wrap in pcall so we can see the actual error
	local ok, err = pcall(function()
		-- Verify gcloud exists
		local _, gcloud_err = run_cmd("gcloud", { "--version" })
		if gcloud_err then
			ya.notify({
				title = "GCS Browser",
				content = "gcloud not found: " .. gcloud_err,
				timeout = 5,
				level = "error",
			})
			return
		end

		local cwd = get_cwd()
		local current_path = nil
		local history = {}

		while true do
			local items, ls_err = gcs_ls(current_path)
			if not items then
				if ls_err then
					ya.notify({ title = "GCS Browser", content = ls_err, timeout = 5, level = "error" })
				end
				break
			end

			-- Hide terminal for fzf interaction
			local permit = ui.hide()
			local result = fzf_pick(items, current_path)
			permit:drop()

			if not result then
				if #history == 0 then
					break
				end
				current_path = table.remove(history)
			elseif result.action == "ctrl-y" then
				copy_path(result.path)
			elseif result.action == "ctrl-d" then
				if result.path:sub(-1) == "/" then
					ya.notify({
						title = "GCS Browser",
						content = "Cannot download a directory",
						timeout = 3,
						level = "warn",
					})
				else
					download(result.path, cwd)
					break
				end
			else
				if result.path:sub(-1) == "/" then
					history[#history + 1] = current_path
					current_path = result.path
				else
					copy_path(result.path)
					break
				end
			end
		end
	end)

	if not ok then
		ya.err("gcs-browser error: " .. tostring(err))
		ya.notify({ title = "GCS Browser", content = tostring(err), timeout = 10, level = "error" })
	end
end

return M
