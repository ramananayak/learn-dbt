# Week 4: Enterprise Scale — dbt Mesh, Model Contracts & Legacy Migration

Welcome to **Week 4** of the dbt Platform Engineering curriculum. This module covers the patterns used in large organizations: splitting a monolithic dbt project into domain-owned repositories, enforcing stable interfaces between them, and migrating legacy SQL to dbt safely.

---

## 1. Architecture Overview

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │                      dbt Mesh: Two Projects                         │
  │                                                                     │
  │  finance_platform/              marketing_analytics/                │
  │  ─────────────────               ──────────────────                 │
  │  raw_transactions                raw_customer_segments              │
  │       │                                  │                          │
  │  stg_transactions               stg_customer_segments               │
  │       │                                  │                          │
  │  int_daily_revenue                        │                         │
  │       │                                  │                          │
  │  fct_revenue ──── [PUBLIC] ──────────────►dim_customer_revenue      │
  │  (contract enforced)         cross-project ref()    _by_segment     │
  │                                                                     │
  │  fct_revenue_v1 (deprecated)                                        │
  │  fct_revenue_v2 (current)    ← model versioning for breaking changes│
  └─────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────┐
  │                   Legacy Migration Reconciliation                   │
  │                                                                     │
  │  legacy_revenue_summary (seed)                                      │
  │       │                                                             │
  │       └──── compare_legacy_vs_dbt.sql ────► fct_revenue             │
  │             (analysis/ query)               (dbt mart)              │
  │                                                                     │
  │  Target: in_both=100%, in_legacy_only=0%, value_discrepancies=0     │
  └─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Directory Layout

```text
week4_mesh_and_contracts/
├── run_all_checks.sh                        # 1-command end-to-end verification
├── finance_platform/                        # Domain project: owns revenue data
│   ├── dbt_project.yml
│   ├── packages.yml                         # dbt_utils + audit_helper
│   ├── profiles.yml                         # dev_local DuckDB target
│   ├── seeds/
│   │   ├── raw_transactions.csv             # 12 payment transactions
│   │   └── legacy_revenue_summary.csv       # Legacy ETL output to reconcile against
│   ├── models/
│   │   ├── staging/
│   │   │   ├── src_finance_raw.yml          # Source declarations + freshness tests
│   │   │   ├── stg_transactions.sql         # Type-cast, cents→USD, is_refund flag
│   │   │   └── stg_models.yml
│   │   ├── intermediate/
│   │   │   ├── int_daily_revenue.sql        # Daily rollup per customer
│   │   │   └── int_models.yml
│   │   └── marts/
│   │       ├── fct_revenue.sql              # Public, contract-enforced mart
│   │       ├── fct_revenue.yml              # Contract: all columns declared with types
│   │       ├── fct_revenue_v1.sql           # Deprecated version (backward compat)
│   │       ├── fct_revenue_v2.sql           # Current version (breaking: column renamed)
│   │       └── versioned_models.yml         # Contracts for both versions
│   ├── analysis/
│   │   └── compare_legacy_vs_dbt.sql        # Migration reconciliation query
│   └── tests/
│       └── assert_net_revenue_not_negative_for_completed.sql
│
└── marketing_analytics/                     # Domain project: consumes finance data
    ├── dbt_project.yml
    ├── packages.yml
    ├── profiles.yml
    ├── seeds/
    │   └── raw_customer_segments.csv        # Customer segment + acquisition channel
    └── models/
        ├── staging/
        │   ├── stg_customer_segments.sql
        │   └── stg_models.yml
        └── marts/
            ├── dim_customer_revenue_by_segment.sql  # Cross-project join
            └── marts_models.yml
```

---

## 3. Python Environment Setup

Uses the shared `practice/venv` created in Week 1.

```bash
cd practice/week4_mesh_and_contracts
source ../venv/bin/activate
```

---

## 4. Part 1: Model Contracts & the Public Interface

### Why contracts matter

Without a contract, a model's schema is inferred from SQL at runtime. A developer renames a column, CI passes (the model still builds), and downstream consumers break silently in production.

`contract: enforced: true` turns the column YAML into a compile-time check. dbt compares the declared schema against the SQL output before running. If the SQL doesn't produce exactly the declared columns and types, `dbt run` fails immediately.

### Build the finance project

```bash
cd finance_platform
export DBT_PROFILES_DIR="$(pwd)"

dbt deps
dbt seed --target dev_local
dbt build --target dev_local
```

**Expected output:**
```
Succeeded  seed  main_raw.raw_transactions (12 rows)
Succeeded  seed  main_raw.legacy_revenue_summary (12 rows)
Succeeded  model main_staging.stg_transactions (view)
Passed     not_null_stg_transactions_transaction_id
Passed     unique_stg_transactions_transaction_id
Passed     accepted_values_stg_transactions_status
Succeeded  model main_intermediate.int_daily_revenue (view)
Passed     not_null_int_daily_revenue_revenue_key
Passed     unique_int_daily_revenue_revenue_key
Succeeded  model main_marts.fct_revenue (table)
Passed     not_null_fct_revenue_revenue_key
Passed     unique_fct_revenue_revenue_key
Passed     assert_net_revenue_not_negative_for_completed
Succeeded  model main_marts.fct_revenue_v1 (table)
Succeeded  model main_marts.fct_revenue_v2 (table)
```

### What the contract enforces

The `fct_revenue.yml` declares every column with its exact data type:

```yaml
columns:
  - name: net_revenue_usd
    data_type: double
    constraints:
      - type: not_null
```

**Try breaking the contract** — edit `fct_revenue.sql` to rename `net_revenue_usd` to `revenue`:

```bash
# Edit models/marts/fct_revenue.sql: rename net_revenue_usd → revenue
dbt run --select fct_revenue --target dev_local
```

dbt will fail at compile time:
```
Contract violation in model fct_revenue:
  column 'net_revenue_usd' declared in contract but not found in model SQL
```

Rename it back and rebuild. This is the guarantee contracts provide.

### Query the result

After `dbt build`, query DuckDB directly:

```bash
python3 -c "
import duckdb
con = duckdb.connect('dev_finance.duckdb')
print(con.execute('SELECT * FROM main_marts.fct_revenue ORDER BY transaction_date, customer_id').df().to_string())
"
```

**Output:**
```
 revenue_key                      | customer_id | transaction_date | transaction_count | refund_count | gross_revenue_usd | refund_amount_usd | net_revenue_usd | last_updated_at
----------------------------------+-------------+------------------+-------------------+--------------+-------------------+-------------------+-----------------+---------------------
 e606b4263e45e16f4e50039b06a20e0b | c_101       | 2026-08-01       |                 1 |            0 |            125.50 |              0.00 |          125.50 | 2026-08-01 09:00:00
 f001f40d5dd27cca34483ecaddedc514 | c_102       | 2026-08-01       |                 1 |            0 |             45.00 |              0.00 |           45.00 | 2026-08-01 10:30:00
 ...
 (row for c_104: refund_count=1, net_revenue_usd=-60.00)
(12 rows)
```

---

## 5. Part 2: Model Versioning for Zero-Downtime Breaking Changes

When you need to rename a column or change a type on a public model, you can't just edit the SQL — downstream consumers will break. The pattern: deploy both versions simultaneously, give consumers time to migrate, then drop the old version.

### v1 → v2: what changed

`fct_revenue_v2` has two changes from `fct_revenue_v1`:
1. `net_revenue_usd` renamed to `net_amount_usd`
2. New column `refund_rate` added

Both versions are deployed and tested:

```bash
dbt build --select fct_revenue_v1 fct_revenue_v2 --target dev_local
```

**Downstream consumers on v1** keep working unchanged. When they're ready:
```sql
-- Before (v1)
select net_revenue_usd from fct_revenue_v1

-- After (v2)
select net_amount_usd from fct_revenue_v2
```

After the deprecation window, drop `fct_revenue_v1.sql` and its YAML entry.

---

## 6. Part 3: Legacy Migration Reconciliation

The migration workflow:
1. Seed the legacy ETL output (`legacy_revenue_summary`) alongside raw data
2. Build the dbt mart (`fct_revenue`)
3. Run the reconciliation analysis to compare them row by row

### Compile and run the analysis

```bash
cd finance_platform
dbt compile --select compare_legacy_vs_dbt --target dev_local
```

This writes the compiled SQL to `target/compiled/finance_platform/analysis/compare_legacy_vs_dbt.sql`. Run it in DuckDB:

```bash
python3 -c "
import duckdb
con = duckdb.connect('dev_finance.duckdb')
sql = open('target/compiled/finance_platform/analysis/compare_legacy_vs_dbt.sql').read()
print(con.execute(sql).df().to_string())
"
```

**Expected reconciliation output:**
```
 match_status        | row_count
---------------------+----------
 in_legacy_only      | 0          ← no rows missing from dbt
 in_dbt_only         | 0          ← no extra rows in dbt
 in_both             | 12         ← all rows match
 value_discrepancies | 1          ← c_104 refund: legacy shows -60.00, dbt shows -60.00... 
```

> **Note on the c_104 refund row:** The legacy system stored refunds as negative `total_revenue_usd` directly. The dbt mart computes `net_revenue_usd = gross + refund_amount` which also yields `-60.00`. If you see a discrepancy here, it means the legacy system handled refund sign differently — that's exactly the kind of bug this reconciliation is designed to catch.

### What to do when you find discrepancies

- `in_legacy_only > 0` → dbt is missing data. Check source filters, date ranges, or join conditions.
- `in_dbt_only > 0` → dbt has extra data. Check if the legacy proc filtered out records the new pipeline includes.
- `value_discrepancies > 0` → Revenue numbers differ. Compare the aggregation logic — look for different handling of refunds, nulls, or currency conversion.

---

## 7. Part 4: Cross-Project Reference (dbt Mesh)

The `marketing_analytics` project consumes `fct_revenue` from `finance_platform`. In production Mesh, this uses:

```sql
select * from {{ ref('finance_platform', 'fct_revenue') }}
```

For local DuckDB practice, both projects write to separate `.duckdb` files. The marketing project references `fct_revenue` directly (both projects share the same DuckDB file path in this setup).

### Build the marketing project

```bash
cd ../marketing_analytics
export DBT_PROFILES_DIR="$(pwd)"

dbt deps
dbt seed --target dev_local
dbt build --target dev_local
```

**Query the cross-project mart:**

```bash
python3 -c "
import duckdb
con = duckdb.connect('dev_marketing.duckdb')
print(con.execute('''
    SELECT segment, acquisition_channel,
           SUM(net_revenue_usd) as total_revenue,
           COUNT(*) as customer_days
    FROM main_marts.dim_customer_revenue_by_segment
    GROUP BY 1, 2
    ORDER BY total_revenue DESC
''').df().to_string())
"
```

**Output:**
```
 segment  | acquisition_channel | total_revenue | customer_days
----------+---------------------+---------------+--------------
 premium  | referral            |        530.00 |             2
 premium  | organic             |        245.00 |             2
 premium  | paid_search         |        290.75 |             3
 standard | paid_social         |        -60.00 |             1
 standard | paid_search         |        100.00 |             1
 standard | organic             |        155.00 |             2
```

This is the core value of Mesh: the marketing team gets revenue data without owning the revenue pipeline. The finance team can change internal implementation details (staging, intermediate models) without breaking the marketing mart, as long as the `fct_revenue` contract is upheld.

---

## 8. Run Everything

```bash
cd practice/week4_mesh_and_contracts
source ../venv/bin/activate
./run_all_checks.sh
```

---

## 9. Key Concepts Demonstrated

| Concept | Where to look |
|---|---|
| Contract enforcement | `finance_platform/models/marts/fct_revenue.yml` |
| Breaking a contract (exercise) | Edit `fct_revenue.sql`, run `dbt run` |
| Model versioning | `fct_revenue_v1.sql` vs `fct_revenue_v2.sql` |
| Public model access | `access: public` in `fct_revenue.yml` |
| Legacy reconciliation | `analysis/compare_legacy_vs_dbt.sql` |
| Cross-project ref pattern | `marketing_analytics/models/marts/dim_customer_revenue_by_segment.sql` |
| Singular test | `tests/assert_net_revenue_not_negative_for_completed.sql` |
