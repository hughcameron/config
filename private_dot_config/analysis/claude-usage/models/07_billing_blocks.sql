-- 07_billing_blocks.sql
-- 5-hour billing window analysis
-- Claude API billing resets after 5 hours of inactivity

CREATE OR REPLACE TABLE agg_billing_blocks AS
WITH ordered_events AS (
    SELECT
        event_timestamp,
        session_id,
        input_tokens,
        output_tokens,
        cache_creation_tokens,
        cache_read_tokens,
        cost_usd,
        model_tier,
        LAG(event_timestamp) OVER (ORDER BY event_timestamp) AS prev_timestamp
    FROM fact_usage
),
with_gaps AS (
    SELECT
        *,
        EXTRACT(EPOCH FROM (event_timestamp - prev_timestamp)) / 3600 AS hours_since_prev,
        CASE
            WHEN prev_timestamp IS NULL THEN 1
            WHEN EXTRACT(EPOCH FROM (event_timestamp - prev_timestamp)) / 3600 > 5 THEN 1
            ELSE 0
        END AS is_new_block
    FROM ordered_events
),
with_block_id AS (
    SELECT
        *,
        SUM(is_new_block) OVER (ORDER BY event_timestamp) AS block_id
    FROM with_gaps
)
SELECT
    block_id,
    MIN(event_timestamp) AS block_start,
    MAX(event_timestamp) AS block_end,
    COUNT(*) AS message_count,
    COUNT(DISTINCT session_id) AS session_count,

    -- Token totals
    SUM(input_tokens) AS input_tokens,
    SUM(output_tokens) AS output_tokens,
    SUM(cache_creation_tokens) AS cache_creation_tokens,
    SUM(cache_read_tokens) AS cache_read_tokens,

    -- Cost
    SUM(cost_usd) AS cost_usd,

    -- Duration and activity
    EXTRACT(EPOCH FROM (MAX(event_timestamp) - MIN(event_timestamp))) / 3600 AS block_duration_hours,

    -- Is this the current active block?
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(event_timestamp))) / 3600 < 5 THEN TRUE
        ELSE FALSE
    END AS is_active,

    -- Hours remaining in current block (if active)
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - MAX(event_timestamp))) / 3600 < 5
        THEN 5 - (EXTRACT(EPOCH FROM (NOW() - MAX(event_timestamp))) / 3600)
        ELSE NULL
    END AS hours_remaining,

    -- Model usage
    STRING_AGG(DISTINCT model_tier, ', ') AS models_used

FROM with_block_id
GROUP BY block_id
ORDER BY block_start DESC;
