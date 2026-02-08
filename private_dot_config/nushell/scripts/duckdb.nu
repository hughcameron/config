
# Alias to Execute file in DuckDB
alias dx = navi --query "duckdb -f <file>" --best-match

# Alias to DuckDB to Visidata
alias dv = navi --query "duckdb -json -f <file> | vd -f json" --best-match

# Alias to DuckDB to JLESS
alias dj = navi --query "duckdb -json -f <file> | jless" --best-match
