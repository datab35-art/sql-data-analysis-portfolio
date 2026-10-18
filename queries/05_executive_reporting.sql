-- ============================================================================
-- EXECUTIVE KPI REPORTING QUERIES
-- Monthly scorecards, YoY comparisons, regional benchmarking
-- ============================================================================

-- 1. Monthly KPI scorecard
WITH monthly_claims AS (
    SELECT
        STRFTIME('%Y-%m', service_date) AS month,
        COUNT(*) AS claim_count,
        SUM(paid_amount) AS total_paid,
        ROUND(SUM(CASE WHEN status = 'denied' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) AS denial_rate
    FROM claims
    GROUP BY 1
),
monthly_calls AS (
    SELECT
        STRFTIME('%Y-%m', call_date) AS month,
        COUNT(*) AS call_count,
        ROUND(AVG(duration_minutes), 1) AS avg_handle_time,
        ROUND(SUM(resolved) * 100.0 / COUNT(*), 1) AS fcr_rate,
        ROUND(AVG(satisfaction_score), 2) AS avg_satisfaction
    FROM calls
    GROUP BY 1
),
monthly_enrollment AS (
    SELECT
        STRFTIME('%Y-%m', enroll_date) AS month,
        COUNT(*) AS new_enrollments
    FROM members
    GROUP BY 1
)
SELECT
    mc.month,
    mc.claim_count,
    ROUND(mc.total_paid, 0) AS total_claims_paid,
    mc.denial_rate,
    ca.call_count,
    ca.avg_handle_time,
    ca.fcr_rate,
    ca.avg_satisfaction,
    COALESCE(me.new_enrollments, 0) AS new_enrollments
FROM monthly_claims mc
LEFT JOIN monthly_calls ca ON mc.month = ca.month
LEFT JOIN monthly_enrollment me ON mc.month = me.month
ORDER BY mc.month;


-- 2. Year-over-year comparison (2024 vs 2025)
WITH yearly_metrics AS (
    SELECT
        STRFTIME('%Y', service_date) AS year,
        COUNT(*) AS claims,
        ROUND(SUM(paid_amount), 2) AS total_paid,
        ROUND(AVG(paid_amount), 2) AS avg_paid,
        ROUND(SUM(CASE WHEN status = 'denied' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) AS denial_rate
    FROM claims
    GROUP BY 1
)
SELECT
    y1.year AS current_year,
    y1.claims AS current_claims,
    y0.claims AS prior_claims,
    ROUND((y1.claims - y0.claims) * 100.0 / NULLIF(y0.claims, 0), 1) AS claims_growth_pct,
    ROUND(y1.total_paid, 0) AS current_paid,
    ROUND(y0.total_paid, 0) AS prior_paid,
    ROUND((y1.total_paid - y0.total_paid) * 100.0 / NULLIF(y0.total_paid, 0), 1) AS paid_growth_pct,
    y1.denial_rate AS current_denial_rate,
    y0.denial_rate AS prior_denial_rate
FROM yearly_metrics y1
LEFT JOIN yearly_metrics y0 ON CAST(y1.year AS INT) = CAST(y0.year AS INT) + 1
WHERE y1.year >= '2025';


-- 3. Regional performance benchmarking
WITH regional AS (
    SELECT
        m.region,
        COUNT(DISTINCT m.member_id) AS members,
        COUNT(c.claim_id) AS claims,
        ROUND(SUM(c.paid_amount), 2) AS total_paid,
        ROUND(AVG(c.paid_amount), 2) AS avg_paid_per_claim,
        ROUND(SUM(CASE WHEN c.status = 'denied' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) AS denial_rate
    FROM members m
    LEFT JOIN claims c ON m.member_id = c.member_id
    GROUP BY m.region
),
regional_calls AS (
    SELECT
        m.region,
        ROUND(AVG(ca.satisfaction_score), 2) AS avg_satisfaction,
        ROUND(SUM(ca.resolved) * 100.0 / COUNT(*), 1) AS fcr_rate,
        ROUND(AVG(ca.duration_minutes), 1) AS avg_handle_time
    FROM calls ca
    JOIN members m ON ca.member_id = m.member_id
    GROUP BY m.region
)
SELECT
    r.region,
    r.members,
    r.claims,
    ROUND(r.claims * 1.0 / r.members, 1) AS claims_per_member,
    ROUND(r.total_paid / r.members, 2) AS cost_per_member,
    r.denial_rate,
    rc.avg_satisfaction,
    rc.fcr_rate,
    rc.avg_handle_time,
    -- Composite score: weighted average of normalized metrics
    ROUND(
        (rc.avg_satisfaction / 10.0) * 0.30 +
        (rc.fcr_rate / 100.0) * 0.25 +
        (1 - r.denial_rate / 100.0) * 0.20 +
        (1 - LEAST(rc.avg_handle_time, 15) / 15.0) * 0.15 +
        (1 - LEAST(r.claims * 1.0 / r.members / 20.0, 1)) * 0.10,
    3) AS composite_score
FROM regional r
JOIN regional_calls rc ON r.region = rc.region
ORDER BY composite_score DESC;


-- 4. Disenrollment risk dashboard
WITH at_risk AS (
    SELECT
        m.member_id,
        m.region,
        m.plan_type,
        COUNT(ca.call_id) AS call_count,
        ROUND(AVG(ca.satisfaction_score), 2) AS avg_satisfaction,
        SUM(CASE WHEN ca.category = 'grievance' THEN 1 ELSE 0 END) AS grievance_count,
        SUM(CASE WHEN ca.resolved = 0 THEN 1 ELSE 0 END) AS unresolved_calls
    FROM members m
    JOIN calls ca ON m.member_id = ca.member_id
    WHERE m.disenroll_date IS NULL
    GROUP BY m.member_id, m.region, m.plan_type
    HAVING AVG(ca.satisfaction_score) < 5.0 OR SUM(CASE WHEN ca.category = 'grievance' THEN 1 ELSE 0 END) > 0
)
SELECT
    region,
    plan_type,
    COUNT(*) AS at_risk_members,
    ROUND(AVG(avg_satisfaction), 2) AS avg_satisfaction,
    SUM(grievance_count) AS total_grievances,
    SUM(unresolved_calls) AS total_unresolved,
    ROUND(AVG(call_count), 1) AS avg_calls
FROM at_risk
GROUP BY region, plan_type
ORDER BY at_risk_members DESC;


-- 5. Executive summary — single-row snapshot of current state
SELECT
    (SELECT COUNT(*) FROM members WHERE disenroll_date IS NULL) AS active_members,
    (SELECT COUNT(*) FROM members WHERE disenroll_date IS NOT NULL) AS disenrolled_members,
    (SELECT ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM members), 1) FROM members WHERE disenroll_date IS NOT NULL) AS disenroll_rate_pct,
    (SELECT COUNT(*) FROM claims WHERE STRFTIME('%Y', service_date) = '2025') AS ytd_claims_2025,
    (SELECT ROUND(SUM(paid_amount), 0) FROM claims WHERE STRFTIME('%Y', service_date) = '2025' AND status = 'paid') AS ytd_paid_2025,
    (SELECT ROUND(SUM(resolved) * 100.0 / COUNT(*), 1) FROM calls WHERE STRFTIME('%Y', call_date) = '2025') AS ytd_fcr_2025,
    (SELECT ROUND(AVG(satisfaction_score), 2) FROM calls WHERE STRFTIME('%Y', call_date) = '2025') AS ytd_satisfaction_2025,
    (SELECT COUNT(DISTINCT provider_id) FROM providers) AS total_providers;
