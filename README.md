# SQL Data Analysis Portfolio — Healthcare Analytics

A collection of SQL queries demonstrating data analysis skills in the healthcare domain: member analytics, claims analysis, call center metrics, provider performance, and executive reporting.

## Business Context

These queries address common analytics needs in healthcare payer organizations — from operational reporting to strategic insights. Each query is written against a normalized relational schema typical of healthcare data warehouses.

## Query Categories

### 1. Member Analytics
- Member demographics and enrollment trends
- Cohort retention analysis
- High-risk member identification
- Member lifetime value estimation

### 2. Claims & Utilization
- Claims volume and cost trending
- Denial rate analysis by category
- Top diagnosis codes and cost drivers
- ER utilization patterns

### 3. Call Center Performance
- Agent productivity metrics
- First Contact Resolution by category
- Handle time distributions
- Repeat caller root cause analysis

### 4. Provider Network
- Provider utilization rankings
- Referral pattern analysis
- Network adequacy checks
- Cost variation across providers

### 5. Executive KPI Reporting
- Monthly KPI scorecards
- Year-over-year comparisons
- Regional performance benchmarking
- Composite quality scores

## Schema

```sql
-- Core tables used across queries
members (member_id, name, dob, gender, region, plan_type, enroll_date, disenroll_date)
claims (claim_id, member_id, provider_id, service_date, diagnosis_code, procedure_code, billed_amount, paid_amount, status)
calls (call_id, member_id, agent_id, call_date, category, duration_minutes, resolved, satisfaction_score)
providers (provider_id, name, specialty, region, network_tier)
enrollments (member_id, plan_type, effective_date, term_date, premium)
```

## Tech Stack

- **SQL** — Written in standard SQL (compatible with PostgreSQL, BigQuery, Snowflake)
- **Python** — SQLite setup script to create and populate a local test database
- **Data** — Synthetic healthcare data generated with Python

## How to Run

```bash
python setup_db.py          # Creates SQLite DB with sample data
sqlite3 healthcare.db       # Open the database
.read queries/01_member_analytics.sql  # Run any query file
```

## Skills Demonstrated

- Complex SQL: CTEs, window functions, subqueries, self-joins
- Healthcare domain analytics (claims, enrollment, utilization)
- KPI design and executive reporting queries
- Data quality checks and validation patterns
- Performance-oriented query patterns
