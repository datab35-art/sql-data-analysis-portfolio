"""Create and populate a SQLite database with synthetic healthcare data."""

import sqlite3
import random
from datetime import datetime, timedelta

import numpy as np

random.seed(42)
np.random.seed(42)

DB_PATH = "healthcare.db"

REGIONS = ["Northeast", "Southeast", "Midwest", "Southwest", "West"]
PLAN_TYPES = ["HMO", "PPO", "EPO", "HDHP"]
SPECIALTIES = [
    "Primary Care", "Cardiology", "Orthopedics", "Dermatology",
    "Pediatrics", "OB/GYN", "Neurology", "Oncology", "Psychiatry", "Radiology",
]
CALL_CATEGORIES = ["billing", "claims", "prescription", "appointment", "benefits", "grievance"]
DIAGNOSIS_CODES = [
    "J06.9", "M54.5", "E11.9", "I10", "J45.909",
    "K21.0", "F41.1", "M79.3", "R10.9", "Z00.00",
    "E78.5", "G43.909", "J20.9", "N39.0", "R51.9",
]
PROCEDURE_CODES = [
    "99213", "99214", "99215", "99203", "99204",
    "36415", "71046", "80053", "85025", "93000",
]


def create_tables(conn):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS members (
            member_id TEXT PRIMARY KEY,
            first_name TEXT,
            last_name TEXT,
            dob DATE,
            gender TEXT,
            region TEXT,
            plan_type TEXT,
            enroll_date DATE,
            disenroll_date DATE
        );

        CREATE TABLE IF NOT EXISTS providers (
            provider_id TEXT PRIMARY KEY,
            provider_name TEXT,
            specialty TEXT,
            region TEXT,
            network_tier TEXT
        );

        CREATE TABLE IF NOT EXISTS claims (
            claim_id TEXT PRIMARY KEY,
            member_id TEXT,
            provider_id TEXT,
            service_date DATE,
            diagnosis_code TEXT,
            procedure_code TEXT,
            billed_amount REAL,
            paid_amount REAL,
            member_responsibility REAL,
            status TEXT,
            FOREIGN KEY (member_id) REFERENCES members(member_id),
            FOREIGN KEY (provider_id) REFERENCES providers(provider_id)
        );

        CREATE TABLE IF NOT EXISTS calls (
            call_id TEXT PRIMARY KEY,
            member_id TEXT,
            agent_id TEXT,
            call_date DATE,
            call_time TEXT,
            category TEXT,
            duration_minutes REAL,
            resolved INTEGER,
            satisfaction_score REAL,
            FOREIGN KEY (member_id) REFERENCES members(member_id)
        );

        CREATE TABLE IF NOT EXISTS enrollments (
            enrollment_id TEXT PRIMARY KEY,
            member_id TEXT,
            plan_type TEXT,
            effective_date DATE,
            term_date DATE,
            monthly_premium REAL,
            FOREIGN KEY (member_id) REFERENCES members(member_id)
        );
    """)


def populate_members(conn, n=2000):
    first_names = ["James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda",
                   "David", "Elizabeth", "William", "Barbara", "Richard", "Susan", "Joseph", "Jessica",
                   "Thomas", "Sarah", "Charles", "Karen", "Daniel", "Lisa", "Matthew", "Nancy"]
    last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
                  "Rodriguez", "Martinez", "Anderson", "Taylor", "Thomas", "Moore", "Jackson", "Lee"]

    rows = []
    for i in range(1, n + 1):
        dob = datetime(1945, 1, 1) + timedelta(days=random.randint(0, 25000))
        enroll = datetime(2020, 1, 1) + timedelta(days=random.randint(0, 1800))
        disenroll = None
        if random.random() < 0.08:
            disenroll = (enroll + timedelta(days=random.randint(90, 1000))).strftime("%Y-%m-%d")

        rows.append((
            f"MBR-{i:05d}",
            random.choice(first_names),
            random.choice(last_names),
            dob.strftime("%Y-%m-%d"),
            random.choice(["M", "F"]),
            random.choice(REGIONS),
            random.choices(PLAN_TYPES, weights=[0.35, 0.30, 0.15, 0.20])[0],
            enroll.strftime("%Y-%m-%d"),
            disenroll,
        ))

    conn.executemany("INSERT INTO members VALUES (?,?,?,?,?,?,?,?,?)", rows)


def populate_providers(conn, n=200):
    rows = []
    for i in range(1, n + 1):
        rows.append((
            f"PRV-{i:04d}",
            f"Dr. Provider_{i}",
            random.choice(SPECIALTIES),
            random.choice(REGIONS),
            random.choices(["Tier 1", "Tier 2", "Tier 3"], weights=[0.50, 0.35, 0.15])[0],
        ))
    conn.executemany("INSERT INTO providers VALUES (?,?,?,?,?)", rows)


def populate_claims(conn, n_members=2000, avg_claims=6):
    rows = []
    claim_id = 0
    for m in range(1, n_members + 1):
        n_claims = max(0, int(np.random.poisson(avg_claims)))
        for _ in range(n_claims):
            claim_id += 1
            svc_date = datetime(2024, 1, 1) + timedelta(days=random.randint(0, 545))
            billed = round(max(50, np.random.lognormal(5.5, 1.2)), 2)
            status = random.choices(["paid", "denied", "pending"], weights=[0.75, 0.15, 0.10])[0]
            paid = round(billed * random.uniform(0.5, 0.95), 2) if status == "paid" else 0
            member_resp = round(billed - paid, 2) if status == "paid" else 0

            rows.append((
                f"CLM-{claim_id:07d}",
                f"MBR-{m:05d}",
                f"PRV-{random.randint(1, 200):04d}",
                svc_date.strftime("%Y-%m-%d"),
                random.choice(DIAGNOSIS_CODES),
                random.choice(PROCEDURE_CODES),
                billed,
                paid,
                member_resp,
                status,
            ))

    conn.executemany("INSERT INTO claims VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    return claim_id


def populate_calls(conn, n_members=2000, avg_calls=3):
    rows = []
    call_id = 0
    agents = [f"AGT-{i:03d}" for i in range(1, 21)]

    for m in range(1, n_members + 1):
        n_calls = max(0, int(np.random.poisson(avg_calls)))
        for _ in range(n_calls):
            call_id += 1
            call_date = datetime(2024, 1, 1) + timedelta(days=random.randint(0, 545))
            hour = random.randint(8, 18)
            minute = random.randint(0, 59)
            category = random.choice(CALL_CATEGORIES)
            duration = max(1.0, round(np.random.normal(7 if category == "grievance" else 5, 2.5), 1))
            resolved = int(random.random() < (0.65 if category == "grievance" else 0.82))
            sat = round(np.clip(np.random.normal(7.0 if resolved else 4.5, 1.5), 1, 10), 1)

            rows.append((
                f"CALL-{call_id:07d}",
                f"MBR-{m:05d}",
                random.choice(agents),
                call_date.strftime("%Y-%m-%d"),
                f"{hour:02d}:{minute:02d}",
                category,
                duration,
                resolved,
                sat,
            ))

    conn.executemany("INSERT INTO calls VALUES (?,?,?,?,?,?,?,?,?)", rows)
    return call_id


def populate_enrollments(conn, n_members=2000):
    rows = []
    eid = 0
    for m in range(1, n_members + 1):
        n_periods = random.randint(1, 3)
        start = datetime(2020, 1, 1) + timedelta(days=random.randint(0, 365))
        for _ in range(n_periods):
            eid += 1
            plan = random.choices(PLAN_TYPES, weights=[0.35, 0.30, 0.15, 0.20])[0]
            term = start + timedelta(days=random.randint(180, 730))
            premium = round(random.uniform(200, 800) if plan != "HDHP" else random.uniform(100, 400), 2)
            rows.append((
                f"ENR-{eid:06d}",
                f"MBR-{m:05d}",
                plan,
                start.strftime("%Y-%m-%d"),
                term.strftime("%Y-%m-%d"),
                premium,
            ))
            start = term + timedelta(days=1)

    conn.executemany("INSERT INTO enrollments VALUES (?,?,?,?,?,?)", rows)


if __name__ == "__main__":
    conn = sqlite3.connect(DB_PATH)
    create_tables(conn)

    print("Populating members...")
    populate_members(conn)

    print("Populating providers...")
    populate_providers(conn)

    print("Populating claims...")
    n_claims = populate_claims(conn)

    print("Populating calls...")
    n_calls = populate_calls(conn)

    print("Populating enrollments...")
    populate_enrollments(conn)

    conn.commit()

    # Summary
    for table in ["members", "providers", "claims", "calls", "enrollments"]:
        count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"  {table}: {count:,} rows")

    conn.close()
    print(f"\nDatabase saved to {DB_PATH}")
