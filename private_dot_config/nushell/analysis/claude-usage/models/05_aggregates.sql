-- 05_aggregates.sql
-- Create time-based aggregate tables

-- Daily aggregates
CREATE OR REPLACE TABLE agg_daily AS
SELECT
    event_date,
    COUNT(*) AS message_count,
    COUNT(DISTINCT session_id) AS session_count,
    SUM(input_tokens) AS input_tokens,
    SUM(output_tokens) AS output_tokens,
    SUM(cache_creation_tokens) AS cache_creation_tokens,
    SUM(cache_read_tokens) AS cache_read_tokens,
    SUM(cost_usd) AS cost_usd
FROM fact_usage
GROUP BY event_date
ORDER BY event_date;

-- Weekly aggregates with week-over-week comparison
CREATE OR REPLACE TABLE agg_weekly AS
WITH weekly AS (
    SELECT
        event_week,
        COUNT(*) AS message_count,
        COUNT(DISTINCT session_id) AS session_count,
        SUM(input_tokens) AS input_tokens,
        SUM(output_tokens) AS output_tokens,
        SUM(cost_usd) AS cost_usd
    FROM fact_usage
    GROUP BY event_week
)
SELECT
    *,
    LAG(cost_usd) OVER (ORDER BY event_week) AS prev_week_cost,
    cost_usd - LAG(cost_usd) OVER (ORDER BY event_week) AS cost_change,
    CASE
        WHEN LAG(cost_usd) OVER (ORDER BY event_week) > 0
        THEN ((cost_usd - LAG(cost_usd) OVER (ORDER BY event_week)) / LAG(cost_usd) OVER (ORDER BY event_week)) * 100
        ELSE NULL
    END AS cost_change_pct
FROM weekly
ORDER BY event_week;

-- Monthly aggregates
CREATE OR REPLACE TABLE agg_monthly AS
SELECT
    event_month,
    COUNT(*) AS message_count,
    COUNT(DISTINCT session_id) AS session_count,
    SUM(input_tokens) AS input_tokens,
    SUM(output_tokens) AS output_tokens,
    SUM(cost_usd) AS cost_usd
FROM fact_usage
GROUP BY event_month
ORDER BY event_month;
