-- 01_load_data.sql
-- Load JSONL files into DuckDB.
--
-- Project ONLY the fields the staging model needs. A naive `SELECT *` here
-- materializes every transcript's full `message.content` (tool results, file
-- dumps, whole message bodies) into raw_usage — ~900MB of JSONL exploded to
-- >12GB in memory and OOM'd the build. We only ever read the model id, the
-- token-usage struct, timestamps, ids and type, so we keep just those. The
-- `message` struct is rebuilt with the two sub-fields staging references
-- (`message.model`, `message.usage.*`) so downstream models are unchanged.
-- `preserve_insertion_order=false` drops the cross-file ordering buffer we
-- don't need (every model re-sorts by timestamp anyway).
SET preserve_insertion_order=false;

CREATE OR REPLACE TABLE raw_usage AS
SELECT
    requestId,
    sessionId,
    cwd,
    type,
    timestamp,
    { model: message.model, usage: message.usage } AS message,
    filename AS source_file
FROM read_ndjson($jsonl_glob, filename=TRUE, ignore_errors=TRUE);
