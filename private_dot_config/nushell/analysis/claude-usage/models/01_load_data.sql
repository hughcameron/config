-- 01_load_data.sql
-- Load JSONL files into DuckDB

-- Load JSONL files (file list passed as JSON array parameter)
CREATE OR REPLACE TABLE raw_usage AS
SELECT *, filename AS source_file
FROM read_ndjson($jsonl_glob, filename=TRUE, ignore_errors=TRUE);
