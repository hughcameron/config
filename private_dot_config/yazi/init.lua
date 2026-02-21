-- DuckDB plugin configuration
require("duckdb"):setup()

require("full-border"):setup()

require("git"):setup {
	-- Order of status signs showing in the linemode
	order = 1500,
}

-- Bookmark manager
require("yamb"):setup {
	-- Use default bookmark storage (persistent across sessions)
}

-- Auto-save/restore session (tabs, directories, view settings)
require("autosession"):setup()

-- Disk usage in header (Linux only, uses df)
require("fs-usage"):setup()

-- GCS browser: header indicator, auto-populate, preview, download
require("gcs-yazi"):setup({
	gcloud_path = "/opt/homebrew/bin/gcloud",
	preview_bytes = 2048,    -- bytes to fetch for file preview (default: 800)
	-- download_dir = "~/Downloads",  -- default
})

