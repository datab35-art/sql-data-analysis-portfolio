-- ============================================================================
-- PROVIDER NETWORK QUERIES
-- Utilization rankings, referral patterns, network adequacy, cost variation
-- ============================================================================

-- 1. Provider utilization rankings — top 20 by claims volume
SELECT
    p.provider_id,
    p.provider_name,
    p.specialty,
    p.region,
    p.network_tier,
    COUNT(c.claim_id) AS claim_count,
    COUNT(DISTINCT c.member_id) AS unique_patients,
    ROUND(SUM(c.paid_amount), 2) AS total_paid,
    ROUND(AVG(c.paid_amount), 2) AS avg_paid_per_claim,
    ROUND(SUM(CASE WHEN c.status = 'denied' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) AS denial_rate
FROM providers p
JOIN claims c ON p.provider_id = c.provider_id
GROUP BY p.provider_id, p.provider_name, p.specialty, p.region, p.network_tier
ORDER BY claim_count DESC
LIMIT 20;


-- 2. Specialty cost comparison across regions
SELECT
    p.specialty,
    p.region,
    COUNT(c.claim_id) AS claims,
    ROUND(AVG(c.billed_amount), 2) AS avg_billed,
    ROUND(AVG(c.paid_amount), 2) AS avg_paid,
    ROUND(STDEV(c.paid_amount), 2) AS std_paid,
    COUNT(DISTINCT p.provider_id) AS providers
FROM providers p
JOIN claims c ON p.provider_id = c.provider_id
WHERE c.status = 'paid'
GROUP BY p.specialty, p.region
HAVING COUNT(*) >= 20
ORDER BY p.specialty, avg_paid DESC;


-- 3. Network tier analysis — cost and quality by tier
SELECT
    p.network_tier,
    COUNT(DISTINCT p.provider_id) AS providers,
    COUNT(c.claim_id) AS total_claims,
    COUNT(DISTINCT c.member_id) AS unique_patients,
    ROUND(AVG(c.billed_amount), 2) AS avg_billed,
    ROUND(AVG(c.paid_amount), 2) AS avg_paid,
    ROUND(SUM(CASE WHEN c.status = 'denied' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 1) AS denial_rate,
    ROUND(SUM(c.paid_amount) / NULLIF(SUM(c.billed_amount), 0) * 100, 1) AS paid_to_billed_pct
FROM providers p
JOIN claims c ON p.provider_id = c.provider_id
GROUP BY p.network_tier
ORDER BY p.network_tier;


-- 4. Provider concentration — claims distribution across providers (Pareto)
WITH provider_volume AS (
    SELECT
        provider_id,
        COUNT(*) AS claims,
        SUM(paid_amount) AS total_paid,
        ROW_NUMBER() OVER (ORDER BY SUM(paid_amount) DESC) AS rank_num
    FROM claims
    WHERE status = 'paid'
    GROUP BY provider_id
),
running_totals AS (
    SELECT
        *,
        SUM(total_paid) OVER (ORDER BY rank_num) AS cumulative_paid,
        SUM(total_paid) OVER () AS grand_total
    FROM provider_volume
)
SELECT
    CASE
        WHEN rank_num <= (SELECT COUNT(DISTINCT provider_id) FROM claims) * 0.1 THEN 'Top 10%'
        WHEN rank_num <= (SELECT COUNT(DISTINCT provider_id) FROM claims) * 0.2 THEN 'Top 10-20%'
        WHEN rank_num <= (SELECT COUNT(DISTINCT provider_id) FROM claims) * 0.5 THEN 'Top 20-50%'
        ELSE 'Bottom 50%'
    END AS provider_percentile,
    COUNT(*) AS providers,
    SUM(claims) AS total_claims,
    ROUND(SUM(total_paid), 2) AS total_paid,
    ROUND(SUM(total_paid) * 100.0 / MAX(grand_total), 1) AS pct_of_spend
FROM running_totals
GROUP BY 1
ORDER BY MIN(rank_num);


-- 5. Network adequacy check — specialty coverage by region
WITH specialty_coverage AS (
    SELECT
        region,
        specialty,
        COUNT(*) AS provider_count,
        SUM(CASE WHEN network_tier = 'Tier 1' THEN 1 ELSE 0 END) AS tier1_count
    FROM providers
    GROUP BY region, specialty
)
SELECT
    region,
    specialty,
    provider_count,
    tier1_count,
    CASE
        WHEN provider_count >= 3 AND tier1_count >= 1 THEN 'Adequate'
        WHEN provider_count >= 1 THEN 'Limited'
        ELSE 'Gap'
    END AS adequacy_status
FROM specialty_coverage
ORDER BY region, specialty;
