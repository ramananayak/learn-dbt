# Week 2: Advanced Incrementals, Redshift Optimization & Snapshots

This project demonstrates the core patterns for **Week 2** of the dbt Platform Engineering curriculum:
1. **Source Configuration & Seed Setup**: Loading raw seed datasets simulating OLTP streaming data into raw schemas.
2. **Staging Layer**: Type casting, cleaning, and validating source relations using `source()` macros.
3. **Optimized Incremental Models**: Redshift `delete+insert` incremental strategy with sort/dist keys, surrogate keys (`dbt_utils.generate_surrogate_key`), and lookback window buffering for late-arriving updates.
4. **SCD Type 2 Snapshots**: Tracking slowly changing customer dimensions with `timestamp` strategy and `invalidate_hard_deletes`.

---

## Directory Layout

```text
week2_advanced_incrementals/
├── dbt_project.yml
├── packages.yml
├── seeds/
│   ├── raw_customers_w2.csv
│   └── raw_orders_w2.csv
├── models/
│   ├── staging/
│   │   ├── src_raw_data.yml
│   │   ├── stg_customers_w2.sql
│   │   ├── stg_orders_w2.sql
│   │   └── stg_models.yml
│   └── marts/
│       ├── fct_daily_customer_orders_w2.sql
│       └── fct_daily_customer_orders.yml
└── snapshots/
    └── snap_customers.sql
```

---

## Step-by-Step Execution Guide

Run the following commands inside this directory using your active Python virtual environment with `--target dev_redshift`.

### 1. Install Packages

```bash
dbt deps --target dev_redshift
```

### 2. Seed Raw Data

Load raw customer and order seeds into `dbt_rnayak_raw`:

```bash
dbt seed
```

**Output:**
```
 Succeeded [4.93s] seed  dbt_rnayak_raw.raw_customers_w2 (table)
 Succeeded [7.21s] seed  dbt_rnayak_raw.raw_orders_w2 (table)
```

**`raw_customers_w2`** (5 rows):
```
 id    | name          | email               | subscription_status | updated_at
-------+---------------+---------------------+---------------------+---------------------
 c_101 | Alice Smith   | alice@example.com   | active              | 2026-08-01 08:00:00
 c_102 | Bob Jones     | bob@example.com     | pending             | 2026-08-01 08:30:00
 c_103 | Charlie Brown | charlie@example.com | active              | 2026-08-02 09:15:00
 c_104 | Diana Prince  | diana@example.com   | cancelled           | 2026-08-02 10:00:00
 c_105 | Evan Wright   | evan@example.com    | active              | 2026-08-03 11:45:00
```

**`raw_orders_w2`** (10 rows):
```
 id     | customer_id | order_date | status    | amount | updated_at
--------+-------------+------------+-----------+--------+---------------------
 o_1001 | c_101       | 2026-08-01 | completed | 125.50 | 2026-08-01 09:00:00
 o_1002 | c_102       | 2026-08-01 | completed |  45.00 | 2026-08-01 10:30:00
 o_1003 | c_101       | 2026-08-02 | completed |  89.90 | 2026-08-02 11:00:00
 o_1004 | c_103       | 2026-08-02 | completed | 210.00 | 2026-08-02 14:15:00
 o_1005 | c_104       | 2026-08-03 | returned  |  60.00 | 2026-08-03 16:00:00
 o_1006 | c_105       | 2026-08-03 | completed | 150.00 | 2026-08-03 17:30:00
 o_1007 | c_101       | 2026-08-04 | completed |  75.25 | 2026-08-04 12:00:00
 o_1008 | c_102       | 2026-08-04 | completed | 110.00 | 2026-08-04 15:45:00
 o_1009 | c_103       | 2026-08-05 | completed | 320.00 | 2026-08-05 09:30:00
 o_1010 | c_105       | 2026-08-05 | completed |  95.00 | 2026-08-05 18:20:00
```

### 3. Build Staging Layer (with source + model tests)

```bash
dbt build --select staging
```

**Output:** 12 total | 12 success (2 models + 10 tests)

**`stg_customers_w2`** — renamed columns, type-cast:
```
 customer_id | customer_name | email               | subscription_status | updated_at
-------------+---------------+---------------------+---------------------+---------------------
 c_101       | Alice Smith   | alice@example.com   | active              | 2026-08-01 08:00:00
 ...
```

**`stg_orders_w2`** — `amount` renamed to `gross_amount_usd`, cast to numeric:
```
 order_id | customer_id | order_date | order_status | gross_amount_usd | updated_at
----------+-------------+------------+--------------+------------------+---------------------
 o_1001   | c_101       | 2026-08-01 | completed    |       125.500000 | 2026-08-01 09:00:00
 ...
```

### 4. Run & Test Incremental Mart

```bash
dbt run --select marts
dbt test --select marts
```

**First run** materializes the full table. The surrogate key is an MD5 hash of `(customer_id, order_date)`:

```
 customer_order_key               | customer_id | order_date | total_orders | total_revenue_usd | last_updated_at
----------------------------------+-------------+------------+--------------+-------------------+---------------------
 e606b4263e45e16f4e50039b06a20e0b | c_101       | 2026-08-01 |            1 |        125.500000 | 2026-08-01 09:00:00
 f001f40d5dd27cca34483ecaddedc514 | c_101       | 2026-08-02 |            1 |         89.900000 | 2026-08-02 11:00:00
 ...
(10 rows)
```

### 5. Execute Snapshot (SCD Type 2)

```bash
dbt snapshot --select snap_customers
```

Captures baseline — all rows have `dbt_valid_to = NULL` (currently active):

```
 customer_id | subscription_status | dbt_valid_from      | dbt_valid_to
-------------+---------------------+---------------------+--------------
 c_101       | active              | 2026-08-01 08:00:00 | [NULL]
 c_102       | pending             | 2026-08-01 08:30:00 | [NULL]
 ...
```

---

## Simulating Incremental Updates

### Scenario: Add new orders + a new customer (c_106)

Update `seeds/raw_orders_w2.csv` and `seeds/raw_customers_w2.csv`, then:

```bash
dbt seed
dbt run --select marts
```

dbt runs `is_incremental()` logic — only processes rows newer than `max(order_date) - 3 days`. New rows for `c_105 (2026-08-06)` and `c_106 (2026-08-06)` are appended; existing rows are untouched.

**Fact table after incremental run** (12 rows — 2 new):
```
 customer_order_key               | customer_id | order_date | total_revenue_usd
----------------------------------+-------------+------------+------------------
 61311c71f7bd38510f47ca6a9cf7fbd8 | c_105       | 2026-08-06 |         95.000000
 b8fae676a11a15496d4f9d709d91cc7d | c_106       | 2026-08-06 |        100.000000
 ... (10 unchanged rows)
```

### Scenario: Customer status change tracked by snapshot

Update `c_106`'s `subscription_status` from `active` → `cancelled` in the seed, then:

```bash
dbt seed
dbt run --select staging
dbt snapshot --select snap_customers
```

The snapshot captures the historical change — old row gets `dbt_valid_to` set, new row is inserted:

```
 customer_id | subscription_status | dbt_valid_from      | dbt_valid_to
-------------+---------------------+---------------------+---------------------
 c_106       | active              | 2026-08-04 11:46:00 | 2026-08-04 12:15:00   ← expired
 c_106       | cancelled           | 2026-08-04 12:15:00 | [NULL]                 ← current
```

This is SCD Type 2 in action: full history preserved, current record always has `dbt_valid_to IS NULL`.
