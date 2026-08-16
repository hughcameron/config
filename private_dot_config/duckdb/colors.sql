# DuckDB highlight colours for the CLI, loaded via the `duckdb` alias in
# ~/.config/zsh/aliases.sh rather than from ~/.duckdbrc.
#
# It cannot live at the default ~/.duckdbrc path: duckdb announces
# "-- Loading resources from <file>" on stderr every time it loads an init
# file, and yazi's duckdb.yazi preloader treats any non-empty stderr as a
# failed preview, deletes the parquet cache it just wrote, and reports the
# preload unfinished — so yazi re-runs it forever. Keeping this off the
# default path leaves yazi's `duckdb` invocation with no init file and
# empty stderr, while interactive shells still get the colours.
.highlight_colors layout gray
.highlight_colors column_name magenta bold
.highlight_colors column_type gray
.highlight_colors string_value cyan
.highlight_colors numeric_value green
.highlight_colors temporal_value blue
.highlight_colors footer gray
