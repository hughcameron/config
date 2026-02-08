-- 04_usage_facts.sql
-- Create core fact table with cost calculations

CREATE OR REPLACE TABLE fact_usage AS
SELECT
    u.event_timestamp,
    u.session_id,
    u.working_directory,
    u.request_id,
    u.message_id,
    u.model_name,
    u.input_tokens,
    u.output_tokens,
    u.cache_creation_tokens,
    u.cache_read_tokens,
    u.source_file,

    -- Date dimensions
    u.event_timestamp::DATE AS event_date,
    DATE_TRUNC('week', u.event_timestamp)::DATE AS event_week,
    DATE_TRUNC('month', u.event_timestamp)::DATE AS event_month,
    EXTRACT(hour FROM u.event_timestamp) AS event_hour,

    -- Model tier classification
    CASE
        WHEN u.model_name ILIKE '%opus%' THEN 'opus'
        WHEN u.model_name ILIKE '%sonnet%' THEN 'sonnet'
        WHEN u.model_name ILIKE '%haiku%' THEN 'haiku'
        ELSE 'unknown'
    END AS model_tier,

    -- Cost calculation
    -- input_tokens = non-cached input (standard rate)
    -- cache_creation_tokens = cached input creation (higher rate)
    -- cache_read_tokens = cached input read (lower rate)
    (
        (u.input_tokens * COALESCE(p.input_cost_per_token, 0)) +
        (u.output_tokens * COALESCE(p.output_cost_per_token, 0)) +
        (u.cache_creation_tokens * COALESCE(p.cache_creation_cost_per_token, 0)) +
        (u.cache_read_tokens * COALESCE(p.cache_read_cost_per_token, 0))
    ) AS cost_usd

FROM stg_usage u
LEFT JOIN dim_pricing p ON u.model_name = p.model_name;
