--- GCS Browser: Browse Google Cloud Storage buckets and objects from yazi.
--- Uses gcloud storage ls + fzf for interactive navigation.
--- Keybinding: g s

local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

--- List GCS path contents via gcloud storage ls.
--- @param path string|nil  nil = list buckets, "gs://bucket/path/" = list contents
--- @return table|nil items  List of full gs:// paths
--- @return string|nil err   Error message if failed
local function gcs_ls(path)
	local cmd
	if path then
		cmd = string.format('gcloud storage ls "%s" 2>&1', path)
	else
		cmd = "gcloud storage ls 2>&1"
	end

	local handle = io.popen(cmd, "r")
	if not handle then
		return nil, "Failed to run gcloud storage ls"
	end

	local output = handle:read("*all") or ""
	handle:close()

	-- Check for errors
	if output:match("^ERROR") or output:match("^CommandException") then
		return nil, output:match("^(.-)\n") or output
	end

	local items = {}
	for line in output:gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$") -- trim
		if #line > 0 then
			table.insert(items, line)
		end
	end

	if #items == 0 then
		return nil, "Empty — no items found"
	end

	return items
end

--- Strip the parent path prefix for cleaner fzf display.
--- Buckets: "gs://my-bucket/" → "my-bucket/"
--- Objects: "gs://bucket/folder/file.txt" with prefix "gs://bucket/folder/" → "file.txt"
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
--- Uses ya.hide() + io.popen() pattern (from yamb.yazi).
--- @param items table  List of full gs:// paths
--- @param current_path string|nil  Current GCS path (nil for bucket root)
--- @return table|nil  { action = "enter"|"ctrl-y"|"ctrl-d", path = "gs://..." }
local function fzf_pick(items, current_path)
	-- Build display names
	local names = {}
	for _, item in ipairs(items) do
		table.insert(names, display_name(item, current_path))
	end

	-- Write items to temp file (avoids all shell escaping issues)
	local tmp = os.tmpname()
	local f = io.open(tmp, "w")
	if not f then
		return nil
	end
	for _, name in ipairs(names) do
		f:write(name .. "\n")
	end
	f:close()

	-- Build header: current location + keybinding hints
	local location = current_path or "GCS Buckets"
	local hints = "Enter=open  Ctrl-Y=copy path  Ctrl-D=download  Esc=back"

	-- Construct fzf command
	-- $'...' allows embedded \n for multi-line header
	local cmd = string.format(
		"fzf --no-sort --expect=ctrl-y,ctrl-d --prompt='GCS > ' --header=$'%s\\n%s' < '%s'",
		location,
		hints,
		tmp
	)

	local permit = ya.hide()
	local handle = io.popen(cmd, "r")
	local result = nil

	if handle then
		local output = handle:read("*all") or ""
		handle:close()

		-- fzf --expect output: line 1 = key pressed, line 2 = selected item
		-- Enter → key is empty; ctrl-y/ctrl-d → key is the name; Esc → empty output
		local key, selected = output:match("^(.-)\n(.-)%s*$")
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
					result = { action = action, path = items[i] }
					break
				end
			end
		end
	end

	permit:drop()
	os.remove(tmp)
	return result
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

	local cmd = string.format('gcloud storage cp "%s" "%s/" 2>&1', gs_path, cwd)
	local handle = io.popen(cmd, "r")
	if handle then
		local output = handle:read("*all") or ""
		handle:close()

		if output:match("^ERROR") or output:match("^CommandException") then
			ya.notify({
				title = "GCS Browser",
				content = "Download failed: " .. (output:match("^(.-)\n") or output),
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
end

--- Main entry point: interactive navigation loop.
return {
	entry = function()
		-- Verify gcloud is available
		local check = io.popen("command -v gcloud 2>/dev/null", "r")
		if check then
			local bin = check:read("*l")
			check:close()
			if not bin or #bin == 0 then
				ya.notify({
					title = "GCS Browser",
					content = "gcloud CLI not found. Install Google Cloud SDK first.",
					timeout = 5,
					level = "error",
				})
				return
			end
		end

		local cwd = get_cwd()
		local current_path = nil -- nil = bucket listing
		local history = {} -- stack for back navigation

		while true do
			local items, err = gcs_ls(current_path)
			if not items then
				if err then
					ya.notify({
						title = "GCS Browser",
						content = err,
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
						content = "Cannot download a directory — select a file",
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
