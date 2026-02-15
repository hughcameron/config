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

-- Directory size calculator
require("what-size"):setup()

