--- Copy the hovered file path, transforming volume mounts to local paths.
--- e.g. /Users/hugh/beelink/foo  -> /home/hugh/foo
--- e.g. /Volumes/Beelink/foo     -> /home/hugh/foo
--- e.g. /tmp/yazi-gcs/bucket/obj -> gs://bucket/obj

local MOUNTS = {
	["/Users/hugh/beelink"] = "/home/hugh",
	["/Volumes/Beelink"] = "/home/hugh",
}

local GCS_TMP = "/tmp/yazi-gcs"

local function transform(path)
	-- GCS temp directory -> gs:// URI
	if path:sub(1, #GCS_TMP) == GCS_TMP and #path > #GCS_TMP then
		return "gs://" .. path:sub(#GCS_TMP + 2)
	end

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
