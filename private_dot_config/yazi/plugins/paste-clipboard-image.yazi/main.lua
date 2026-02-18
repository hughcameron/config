--- Paste clipboard image to a file using pngpaste (macOS)
local M = {}

local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

function M:entry()
	local cwd = get_cwd()

	-- Prompt for filename (default to clipboard.png)
	local name, event = ya.input({
		title = "Paste clipboard image as:",
		value = "clipboard.png",
		position = { "center", w = 60 },
	})

	if event ~= 1 or not name or name == "" then
		return
	end

	-- Ensure it has an image extension, default to .png
	if not name:match("%.[a-zA-Z]+$") then
		name = name .. ".png"
	end

	local path = cwd .. "/" .. name

	-- Check if file exists
	local cha, _ = fs.cha(Url(path))
	if cha then
		local overwrite = ya.confirm({
			title = "File exists",
			content = ui.Text({
				ui.Line(""),
				ui.Line("Overwrite " .. name .. "?"):style(ui.Style():fg("yellow")),
			}):align(ui.Align.CENTER),
			position = { "center", w = 60, h = 8 },
		})
		if not overwrite then
			return
		end
	end

	-- Run pngpaste to save clipboard image
	local child, err = Command("pngpaste"):arg(path):spawn()
	if not child then
		ya.notify({
			title = "Paste image",
			content = "Failed to run pngpaste: " .. (err or "unknown error"),
			timeout = 3,
			level = "error",
		})
		return
	end

	local output = child:wait()
	if not output or not output.success then
		ya.notify({
			title = "Paste image",
			content = "No image in clipboard (or pngpaste failed)",
			timeout = 3,
			level = "warn",
		})
		return
	end

	-- Reveal the new file
	ya.notify({
		title = "Paste image",
		content = "Saved " .. name,
		timeout = 2,
		level = "info",
	})
	ya.emit("reveal", { path })
end

return M
