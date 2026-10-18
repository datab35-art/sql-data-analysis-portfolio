-- ============================================================================
-- CLAIMS & UTILIZATION QUERIES
-- Claims trending, denial analysis, cost drivers, ER patterns
-- ============================================================================

-- 1. Monthly claims volume and cost trending
SELECT
    STRFTIME('%Y-%m', service_date) AS month,
    COUNT(*) AS claim_count,
    SUM(CASE WHEN status = 'paid' THEN 1 ELSE 0 END) AS paid_claims,
    SUM(CASE WHEN status = 'denied' THEN 1 ELSE 0 END) AS denied_claims,
    ROUND(SUM(billed_amount), 2) AS total_billed,
    ROUND(SUM(paid_amount), 2) AS total_paid,
    ROUND(AVG(billed_amount), 2) AS avg_billed_per_claim,
    ROUND(SUM(CASE WHEN status = 'denied' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) AS denial_rate_pct
FROM claims
GROUP BY 1
ORDER BY 1;


-- 2. Denial rate analysis by diagnosis code (top 15 most denied)
WITH denial_stats AS (
    SELECT
        diagnosis_code,
        COUNT(*) AS total_claims,
        SUM(CASE WHEN status = 'denied' THEN 1 ELSE 0 END) AS denied_count,
        ROUND(SUM(CASE WHEN status = 'denied' THEN billed_amount ELSE 0 END), 2) AS denied_dollars,
        ROUND(SUM(CASE WHEN status = 'denied' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) AS denial_rate
    FROM claims
    GROUP BY diagnosis_code
    HAVING COUNT(*) >= 50
)
SELECT *
FROM denial_stats
ORDER BY denial_rate DESC
LIMIT 15;


-- 3. Top cost drivers — diagnosis codes by total paid amount
SELECT
    c.diagnosis_code,
    COUNT(*) AS claim_count,
    COUNT(DISTINCT c.member_id) AS unique_members,
    ROUND(SUM(c.paid_amount), 2) AS total_paid,
    ROUND(AVG(c.paid_amount), 2) AS avg_paid_per_claim,
    ROUND(SUM(c.paid_amount) * 100.0 / (SELECT SUM(paid_amount) FROM claims WHERE status = 'paid'), 1) AS pct_of_total_spend
FROM claims c
WHERE c.status = 'paid'
GROUP BY c.diagnosis_code
ORDER BY total_paid DESC
LIMIT 10;


-- 4. Claims per member distribution with cost percentiles
WITH member_claims AS (
    SELECT
        member_id,
        COUNT(*) AS claims,
        SUM(paid_amount) AS total_paid
    FROM claims
    GROUP BY member_id
)
SELECT
    CASE
        WHEN claims <= 2 THEN '0-2 claims'
        WHEN claims <= 5 THEN '3-5 claims'
        WHEN claims <= 10 THEN '6-10 claims'
        WHEN claims <= 20 THEN '11-20 claims'
        ELSE '20+ claims'
    END AS claim_bucket,
    COUNT(*) AS members,
    ROUND(AVG(claims), 1) AS avg_claims,
    ROUND(AVG(total_paid), 2) AS avg_total_paid,
    ROUND(SUM(total_paid), 2) AS bucket_total_paid,
    ROUND(SUM(total_paid) * 100.0 / (SELECT SUM(total_paid) FROM member_claims), 1) AS pct_of_spend
FROM member_claims
GROUP BY 1
ORDER BY MIN(claims);


-- 5. Month-over-month claim cost growth rate
WITH monthly AS (
    SELECT
        STRFTIME('%Y-%m', service_date) AS month,
        SUM(paid_amount) AS total_paid
    FROM claims
    WHERE status = 'paid'
    GROUP BY 1
),
growth AS (
    SELECT
        month,
        total_paid,
        LAG(total_paid) OVER (ORDER BY month) AS prev_month_paid,
        ROUND((total_paid - LAG(total_paid) OVER (ORDER BY month))
              / LAG(total_paid) OVER (ORDER BY month) * 100, 1) AS mom_growth_pct
    FROM monthly
)
SELECT * FROM growth ORDER BY month;


-- 6. Paid-to-billed ratio by provider specialty
SELECT
    p.specialty,
    COUNT(c.claim_id) AS claims,
    ROUND(SUM(c.billed_amount), 2) AS total_billed,
    ROUND(SUM(c.paid_amount), 2) AS total_paid,
    ROUND(SUM(c.paid_amount) / NULLIF(SUM(c.billed_amount), 0) * 100, 1) AS paid_to_billed_pct,
    ROUND(AVG(c.billed_amount), 2) AS avg_billed
FROM claims c
JOIN providers p ON c.provider_id = p.provider_id
WHERE c.status = 'paid'
GROUP BY p.specialty
ORDER BY paid_to_billed_pct;
