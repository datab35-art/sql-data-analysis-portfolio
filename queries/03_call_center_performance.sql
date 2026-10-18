-- ============================================================================
-- CALL CENTER PERFORMANCE QUERIES
-- Agent metrics, FCR, handle time, repeat callers
-- ============================================================================

-- 1. Agent productivity scorecard
SELECT
    agent_id,
    COUNT(*) AS total_calls,
    ROUND(AVG(duration_minutes), 1) AS avg_handle_time,
    ROUND(SUM(resolved) * 100.0 / COUNT(*), 1) AS resolution_rate,
    ROUND(AVG(satisfaction_score), 2) AS avg_satisfaction,
    SUM(CASE WHEN satisfaction_score >= 8 THEN 1 ELSE 0 END) AS high_sat_calls,
    SUM(CASE WHEN satisfaction_score <= 3 THEN 1 ELSE 0 END) AS low_sat_calls
FROM calls
GROUP BY agent_id
ORDER BY avg_satisfaction DESC;


-- 2. First Contact Resolution by category
SELECT
    category,
    COUNT(*) AS total_calls,
    SUM(resolved) AS resolved_first_contact,
    ROUND(SUM(resolved) * 100.0 / COUNT(*), 1) AS fcr_rate,
    ROUND(AVG(duration_minutes), 1) AS avg_handle_time,
    ROUND(AVG(satisfaction_score), 2) AS avg_satisfaction
FROM calls
GROUP BY category
ORDER BY fcr_rate;


-- 3. Handle time distribution — buckets with satisfaction correlation
SELECT
    CASE
        WHEN duration_minutes <= 3 THEN '0-3 min'
        WHEN duration_minutes <= 5 THEN '3-5 min'
        WHEN duration_minutes <= 8 THEN '5-8 min'
        WHEN duration_minutes <= 12 THEN '8-12 min'
        ELSE '12+ min'
    END AS handle_time_bucket,
    COUNT(*) AS calls,
    ROUND(AVG(satisfaction_score), 2) AS avg_satisfaction,
    ROUND(SUM(resolved) * 100.0 / COUNT(*), 1) AS resolution_rate,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM calls), 1) AS pct_of_calls
FROM calls
GROUP BY 1
ORDER BY MIN(duration_minutes);


-- 4. Repeat caller analysis — members with 5+ calls
WITH caller_stats AS (
    SELECT
        member_id,
        COUNT(*) AS call_count,
        COUNT(DISTINCT category) AS categories_contacted,
        ROUND(AVG(satisfaction_score), 2) AS avg_satisfaction,
        ROUND(SUM(resolved) * 100.0 / COUNT(*), 1) AS resolution_rate,
        MIN(call_date) AS first_call,
        MAX(call_date) AS last_call
    FROM calls
    GROUP BY member_id
    HAVING COUNT(*) >= 5
)
SELECT
    cs.*,
    ROUND(JULIANDAY(cs.last_call) - JULIANDAY(cs.first_call), 0) AS days_span,
    m.region,
    m.plan_type
FROM caller_stats cs
JOIN members m ON cs.member_id = m.member_id
ORDER BY cs.call_count DESC
LIMIT 25;


-- 5. Hourly call volume pattern
SELECT
    SUBSTR(call_time, 1, 2) AS hour,
    COUNT(*) AS call_count,
    ROUND(AVG(duration_minutes), 1) AS avg_handle_time,
    ROUND(AVG(satisfaction_score), 2) AS avg_satisfaction,
    ROUND(SUM(resolved) * 100.0 / COUNT(*), 1) AS resolution_rate
FROM calls
GROUP BY 1
ORDER BY 1;


-- 6. Call volume trend with rolling 7-day average
WITH daily AS (
    SELECT
        call_date,
        COUNT(*) AS daily_calls,
        ROUND(AVG(satisfaction_score), 2) AS daily_sat
    FROM calls
    GROUP BY call_date
)
SELECT
    call_date,
    daily_calls,
    daily_sat,
    ROUND(AVG(daily_calls) OVER (
        ORDER BY call_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 1) AS rolling_7d_avg_calls,
    ROUND(AVG(daily_sat) OVER (
        ORDER BY call_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_7d_avg_sat
FROM daily
ORDER BY call_date;
