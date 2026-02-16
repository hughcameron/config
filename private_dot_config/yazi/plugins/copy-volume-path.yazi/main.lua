--- Copy the hovered file path, transforming volume mounts to local paths.
--- e.g. /Volumes/Beelink/foo → /home/hugh/foo

local MOUNTS = {
	["/Volumes/Beelink"] = "/home/hugh",
}

local function transform(path)
	for prefix, replacement in pairs(MOUNTS) do
		if path:sub(1, #prefix) == prefix then
			return replacement .. path:sub(#prefix + 1)
		end
	end
	return path
end

local get_path = ya.sync(function()
	local hovered = cx.active.current.hovered
	if hovered then
		return tostring(hovered.url)
	end
	return nil
end)

return {
	entry = function()
		local path = get_path()
		if not path then
			ya.notify {
				title = "Copy volume path",
				content = "No file hovered",
				timeout = 3,
				level = "warn",
			}
			return
		end

		local transformed = transform(path)
		ya.clipboard(transformed)
		ya.notify {
			title = "Copied",
			content = transformed,
			timeout = 3,
		}
	end,
}
