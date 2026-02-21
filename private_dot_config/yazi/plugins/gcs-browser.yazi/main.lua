--- GCS Browser: Browse Google Cloud Storage buckets and objects from yazi.
--- Uses gcloud storage ls + fzf for interactive navigation.
--- Keybinding: g s
--- @since 26.2.2

local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local TMP_PATH = "/tmp/yazi-gcs-items.txt"

--- List GCS path contents via gcloud storage ls.
--- Uses yazi's Command() API (not io.popen which is sandboxed in 26.x).
--- @param path string|nil  nil = list buckets, "gs://bucket/path/" = list contents
--- @return table|nil items  List of full gs:// paths
--- @return string|nil err   Error message if failed
local function gcs_ls(path)
	local args = { "storage", "ls" }
	if path then
		table.insert(args, path)
	end

	local output, err = Command("gcloud"):arg(args):stdout(Command.PIPED):stderr(Command.PIPED):output()
	if err then
		return nil, "gcloud error: " .. err
	end
	if not output.status.success then
		local msg = output.stderr or ""
		return nil, msg:match("^(.-)\n") or msg
	end

	local items = {}
	for line in output.stdout:gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$") -- trim
		if #line > 0 then
			table.insert(items, line)
		end
	end

	if #items == 0 then
		return nil, "Empty -- no items found"
	end

	return items
end

--- Strip the parent path prefix for cleaner fzf display.
--- Buckets: "gs://my-bucket/" -> "my-bucket/"
--- Objects: "gs://bucket/folder/file.txt" with prefix "gs://bucket/folder/" -> "file.txt"
--- @param item string  Full gs:// path
--- @param prefix string|nil  Parent path to strip (nil for bucket listing)
--- @return string  Display name
local function display_name(item, prefix)
	if not prefix then
		-- Bucket listing: strip gs:// prefix, keep trailing /
		local name = item:match("^gs://(.+)$")
		return name or item
	end
	-- Strip parent path prefix
	local name = item:sub(#prefix + 1)
	if #name == 0 then
		return item
	end
	return name
end

--- Show items in fzf and return the user's selection.
--- Uses ui.hide() + Command("sh") for fzf (interactive TUI needs terminal).
--- Items written via fs.write() (yazi-native, no io.open needed).
--- @param items table  List of full gs:// paths
--- @param current_path string|nil  Current GCS path (nil for bucket root)
--- @return table|nil  { action = "enter"|"ctrl-y"|"ctrl-d", path = "gs://..." }
local function fzf_pick(items, current_path)
	-- Build display names
	local names = {}
	for _, item in ipairs(items) do
		table.insert(names, display_name(item, current_path))
	end

	-- Build file content: first 2 lines are header, rest are selectable items
	local location = current_path or "GCS Buckets"
	local hints = "Enter=open  Ctrl-Y=copy path  Ctrl-D=download  Esc=back"
	local lines = { location, hints }
	for _, name in ipairs(names) do
		table.insert(lines, name)
	end
	local content = table.concat(lines, "\n") .. "\n"

	-- Write to temp file using yazi's fs API
	local tmp_url = Url(TMP_PATH)
	fs.write(tmp_url, content)

	-- Run fzf via sh — header-lines=2 uses first 2 lines as sticky header
	local fzf_cmd = string.format(
		"fzf --no-sort --expect=ctrl-y,ctrl-d --prompt='GCS > ' --header-lines=2 < '%s'",
		TMP_PATH
	)

	local permit = ui.hide()
	local output, err = Command("sh"):arg({ "-c", fzf_cmd }):stdout(Command.PIPED):output()
	permit:drop()

	-- Cleanup temp file
	fs.remove("file", tmp_url)

	if err or not output then
		return nil
	end

	-- Parse fzf --expect output: line 1 = key pressed, line 2 = selected item
	-- Enter -> key is empty; ctrl-y/ctrl-d -> key is the name; Esc -> empty stdout
	local stdout = output.stdout or ""
	local key, selected = stdout:match("^(.-)\n(.-)%s*$")
	if selected and #selected > 0 then
		-- Map display name back to full path
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
	end

	return nil
end

--- Copy a gs:// path to the system clipboard.
--- @param path string  Full gs:// path
local function copy_path(path)
	ya.clipboard(path)
	ya.notify({
		title = "GCS Browser",
		content = "Copied: " .. path,
		timeout = 3,
	})
end

--- Download a GCS object to the specified local directory.
--- @param gs_path string  Full gs:// path to the object
--- @param cwd string  Local directory to download into
local function download(gs_path, cwd)
	ya.notify({
		title = "GCS Browser",
		content = "Downloading...",
		timeout = 2,
	})

	local output, err = Command("gcloud")
		:arg({ "storage", "cp", gs_path, cwd .. "/" })
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if err then
		ya.notify({
			title = "GCS Browser",
			content = "Download error: " .. err,
			timeout = 5,
			level = "error",
		})
	elseif not output.status.success then
		local msg = output.stderr or "Unknown error"
		ya.notify({
			title = "GCS Browser",
			content = "Download failed: " .. (msg:match("^(.-)\n") or msg),
			timeout = 5,
			level = "error",
		})
	else
		local filename = gs_path:match("([^/]+)$") or gs_path
		ya.notify({
			title = "GCS Browser",
			content = "Downloaded: " .. filename,
			timeout = 3,
		})
	end
end

--- Main entry point: interactive navigation loop.
return {
	entry = function()
		-- Verify gcloud is available
		local output, err =
			Command("gcloud"):arg({ "--version" }):stdout(Command.PIPED):stderr(Command.PIPED):output()
		if err or not output or not output.status.success then
			ya.notify({
				title = "GCS Browser",
				content = "gcloud CLI not found. Install Google Cloud SDK first.",
				timeout = 5,
				level = "error",
			})
			return
		end

		local cwd = get_cwd()
		local current_path = nil -- nil = bucket listing
		local history = {} -- stack for back navigation

		while true do
			local items, ls_err = gcs_ls(current_path)
			if not items then
				if ls_err then
					ya.notify({
						title = "GCS Browser",
						content = ls_err,
						timeout = 5,
						level = "error",
					})
				end
				break
			end

			local result = fzf_pick(items, current_path)

			if not result then
				-- Esc pressed: go back one level or exit
				if #history == 0 then
					break
				end
				current_path = table.remove(history)
			elseif result.action == "ctrl-y" then
				-- Copy gs:// path to clipboard (stay in browser)
				copy_path(result.path)
			elseif result.action == "ctrl-d" then
				-- Download file to current yazi directory
				if result.path:sub(-1) == "/" then
					ya.notify({
						title = "GCS Browser",
						content = "Cannot download a directory -- select a file",
						timeout = 3,
						level = "warn",
					})
				else
					download(result.path, cwd)
					break
				end
			else
				-- Enter: navigate into directory, or copy file path
				if result.path:sub(-1) == "/" then
					table.insert(history, current_path)
					current_path = result.path
				else
					copy_path(result.path)
					break
				end
			end
		end
	end,
}
