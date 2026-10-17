-- ============================================================================
-- MEMBER ANALYTICS QUERIES
-- Healthcare member demographics, enrollment trends, and cohort analysis
-- ============================================================================

-- 1. Member demographics summary by region and plan type
SELECT
    region,
    plan_type,
    COUNT(*) AS member_count,
    ROUND(AVG((JULIANDAY('2025-06-01') - JULIANDAY(dob)) / 365.25), 1) AS avg_age,
    SUM(CASE WHEN gender = 'M' THEN 1 ELSE 0 END) AS male_count,
    SUM(CASE WHEN gender = 'F' THEN 1 ELSE 0 END) AS female_count,
    ROUND(AVG(JULIANDAY('2025-06-01') - JULIANDAY(enroll_date)), 0) AS avg_days_enrolled
FROM members
WHERE disenroll_date IS NULL
GROUP BY region, plan_type
ORDER BY region, member_count DESC;


-- 2. Monthly enrollment trend (new enrollments vs disenrollments)
WITH months AS (
    SELECT DISTINCT STRFTIME('%Y-%m', enroll_date) AS month FROM members
    UNION
    SELECT DISTINCT STRFTIME('%Y-%m', disenroll_date) FROM members WHERE disenroll_date IS NOT NULL
),
new_enrollments AS (
    SELECT STRFTIME('%Y-%m', enroll_date) AS month, COUNT(*) AS new_members
    FROM members
    GROUP BY 1
),
disenrollments AS (
    SELECT STRFTIME('%Y-%m', disenroll_date) AS month, COUNT(*) AS lost_members
    FROM members
    WHERE disenroll_date IS NOT NULL
    GROUP BY 1
)
SELECT
    m.month,
    COALESCE(ne.new_members, 0) AS new_enrollments,
    COALESCE(d.lost_members, 0) AS disenrollments,
    COALESCE(ne.new_members, 0) - COALESCE(d.lost_members, 0) AS net_change
FROM months m
LEFT JOIN new_enrollments ne ON m.month = ne.month
LEFT JOIN disenrollments d ON m.month = d.month
ORDER BY m.month;


-- 3. Cohort retention analysis — enrollment month cohort, retained at 6/12 months
WITH cohorts AS (
    SELECT
        member_id,
        STRFTIME('%Y-%m', enroll_date) AS cohort_month,
        enroll_date,
        disenroll_date
    FROM members
),
retention AS (
    SELECT
        cohort_month,
        COUNT(*) AS cohort_size,
        SUM(CASE
            WHEN disenroll_date IS NULL
              OR JULIANDAY(disenroll_date) - JULIANDAY(enroll_date) >= 180
            THEN 1 ELSE 0
        END) AS retained_6m,
        SUM(CASE
            WHEN disenroll_date IS NULL
              OR JULIANDAY(disenroll_date) - JULIANDAY(enroll_date) >= 365
            THEN 1 ELSE 0
        END) AS retained_12m
    FROM cohorts
    GROUP BY cohort_month
)
SELECT
    cohort_month,
    cohort_size,
    retained_6m,
    ROUND(retained_6m * 100.0 / cohort_size, 1) AS retention_6m_pct,
    retained_12m,
    ROUND(retained_12m * 100.0 / cohort_size, 1) AS retention_12m_pct
FROM retention
ORDER BY cohort_month;


-- 4. High-utilization members (top 5% by claim count) with their cost profile
WITH member_claims AS (
    SELECT
        m.member_id,
        m.region,
        m.plan_type,
        COUNT(c.claim_id) AS claim_count,
        SUM(c.billed_amount) AS total_billed,
        SUM(c.paid_amount) AS total_paid,
        SUM(c.member_responsibility) AS total_member_cost,
        COUNT(DISTINCT c.diagnosis_code) AS unique_diagnoses
    FROM members m
    JOIN claims c ON m.member_id = c.member_id
    GROUP BY m.member_id, m.region, m.plan_type
),
percentiles AS (
    SELECT *, NTILE(20) OVER (ORDER BY claim_count) AS ventile
    FROM member_claims
)
SELECT
    member_id,
    region,
    plan_type,
    claim_count,
    ROUND(total_billed, 2) AS total_billed,
    ROUND(total_paid, 2) AS total_paid,
    unique_diagnoses
FROM percentiles
WHERE ventile = 20
ORDER BY claim_count DESC
LIMIT 20;


-- 5. Member lifetime value estimate (avg monthly premium × avg tenure)
WITH member_value AS (
    SELECT
        m.member_id,
        m.plan_type,
        m.region,
        AVG(e.monthly_premium) AS avg_premium,
        ROUND((JULIANDAY(COALESCE(m.disenroll_date, '2025-06-01')) - JULIANDAY(m.enroll_date)) / 30.44, 0) AS tenure_months,
        SUM(c.paid_amount) AS total_claims_paid
    FROM members m
    LEFT JOIN enrollments e ON m.member_id = e.member_id
    LEFT JOIN claims c ON m.member_id = c.member_id
    GROUP BY m.member_id, m.plan_type, m.region
)
SELECT
    plan_type,
    region,
    COUNT(*) AS members,
    ROUND(AVG(avg_premium), 2) AS avg_monthly_premium,
    ROUND(AVG(tenure_months), 1) AS avg_tenure_months,
    ROUND(AVG(avg_premium * tenure_months), 2) AS avg_lifetime_revenue,
    ROUND(AVG(total_claims_paid), 2) AS avg_lifetime_claims,
    ROUND(AVG(avg_premium * tenure_months) - AVG(total_claims_paid), 2) AS avg_lifetime_margin
FROM member_value
GROUP BY plan_type, region
ORDER BY avg_lifetime_margin DESC;
