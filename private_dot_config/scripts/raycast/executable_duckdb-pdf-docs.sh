#!/bin/bash

# Dependency: This script requires `docker for mac` to be installed: https://docs.docker.com/docker-for-mac/install/
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title DuckDB PDF Docs
# @raycast.mode fullOutput
#
# Optional parameters:
# @raycast.icon images/duckdb.png
# @raycast.packageName DuckDB PDF Docs
#
# @raycast.description Download and open DuckDB PDF Docs
# @raycast.author Hugh Cameron
# @raycase.authorURL https://github.com/hughcameron

curl https://duckdb.org/duckdb-docs.pdf -o ~/.duckdb/docs.pdf

open ~/.duckdb/docs.pdf
