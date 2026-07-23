-- 06_sessions.sql
-- Session-level metrics and analysis

CREATE OR REPLACE TABLE agg_sessions AS
SELECT
    session_id,
    MIN(event_timestamp) AS session_start,
    MAX(event_timestamp) AS session_end,
    EXTRACT(EPOCH FROM (MAX(event_timestamp) - MIN(event_timestamp))) / 60 AS duration_minutes,
    COUNT(*) AS message_count,

    -- Token totals
    SUM(input_tokens) AS input_tokens,
    SUM(output_tokens) AS output_tokens,
    SUM(cache_creation_tokens) AS cache_creation_tokens,
    SUM(cache_read_tokens) AS cache_read_tokens,

    -- Cost
    SUM(cost_usd) AS cost_usd,

    -- Working directory (most common)
    MODE(working_directory) AS primary_working_directory,

    -- Models used
    STRING_AGG(DISTINCT model_tier, ', ') AS models_used,

    -- Model tier breakdown
    SUM(CASE WHEN model_tier = 'opus' THEN cost_usd ELSE 0 END) AS opus_cost,
    SUM(CASE WHEN model_tier = 'sonnet' THEN cost_usd ELSE 0 END) AS sonnet_cost,
    SUM(CASE WHEN model_tier = 'haiku' THEN cost_usd ELSE 0 END) AS haiku_cost

FROM fact_usage
GROUP BY session_id
ORDER BY session_start DESC;
