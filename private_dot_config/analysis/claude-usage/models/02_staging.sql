-- 02_staging.sql
-- Aggregate tokens per request (taking MAX to handle streaming updates)
-- Streaming records report cumulative token counts, so MAX gives the final count

CREATE OR REPLACE TABLE stg_usage AS
WITH aggregated AS (
    SELECT
        requestId AS request_id,
        sessionId AS session_id,
        cwd AS working_directory,
        message.model AS model_name,
        -- Take MAX of each token field per request (handles streaming)
        MAX(message.usage.input_tokens) AS input_tokens,
        MAX(message.usage.output_tokens) AS output_tokens,
        MAX(COALESCE(message.usage.cache_creation_input_tokens, 0)) AS cache_creation_tokens,
        MAX(COALESCE(message.usage.cache_read_input_tokens, 0)) AS cache_read_tokens,
        -- Constant within a request, but AGGREGATED rather than grouped: a NULL
        -- on one streaming record would otherwise split the request into two rows
        -- and double-count its tokens.
        BOOL_OR(is_sidechain) AS is_sidechain,
        MAX(git_branch) AS git_branch,
        -- Take the latest timestamp and source file
        MAX(timestamp) AS event_timestamp,
        MAX(source_file) AS source_file
    FROM raw_usage
    WHERE type = 'assistant'
      AND message.usage IS NOT NULL
      AND message.usage.input_tokens IS NOT NULL
    GROUP BY requestId, sessionId, cwd, message.model
)
SELECT
    event_timestamp::TIMESTAMP AS event_timestamp,
    session_id,
    working_directory,
    request_id,
    request_id AS message_id,  -- Use request_id as dedup key
    model_name,
    input_tokens,
    output_tokens,
    cache_creation_tokens,
    cache_read_tokens,
    is_sidechain,
    git_branch,
    source_file
FROM aggregated
WHERE request_id IS NOT NULL;
