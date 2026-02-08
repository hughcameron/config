#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title DuckDB HTML Docs
# @raycast.mode fullOutput
#
# Optional parameters:
# @raycast.icon images/duckdb.png
# @raycast.packageName DuckDB HTML Docs
#
# @raycast.description Download and open DuckDB HTML Docs
# @raycast.author Hugh Cameron
# @raycase.authorURL https://github.com/hughcameron

# curl https://duckdb.org/duckdb-docs.zip -o ~/.duckdb/docs.zip

unzip -o ~/.duckdb/docs.zip -d ~/.duckdb/docs

cd ~/.duckdb/docs/duckdb-docs

python3 -m http.server

open http://localhost:8000
