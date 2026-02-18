local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local function entry()
	local cwd = get_cwd()

	local name, event = ya.input({
		title = "Paste clipboard image as:",
		value = os.date("%Y-%m-%d_%H-%M-%S") .. ".png",
		pos = { "center", w = 60 },
	})

	if event ~= 1 or not name or name == "" then
		return
	end

	if not name:match("%.[a-zA-Z]+$") then
		name = name .. ".png"
	end

	local path = cwd .. "/" .. name

	local status, err = Command("pngpaste")
		:arg(path)
		:stderr(Command.PIPED)
		:status()

	if not status or not status.success then
		ya.notify({
			title = "Paste image",
			content = "No image in clipboard (or pngpaste failed)",
			timeout = 3,
			level = "warn",
		})
		return
	end

	ya.notify({
		title = "Paste image",
		content = "Saved " .. name,
		timeout = 2,
		level = "info",
	})
end

return { entry = entry }
