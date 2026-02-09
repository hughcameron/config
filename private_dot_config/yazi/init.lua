-- DuckDB plugin configuration
require("duckdb"):setup()

require("full-border"):setup()

require("vcs-files"):setup {
	-- Order of status signs showing in the linemode
	order = 1500,
}

