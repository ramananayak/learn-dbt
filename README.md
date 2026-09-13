# dbt Platform Engineering Master Practice

[Official dbt Documentation](https://docs.getdbt.com/) | [dbt Platform Engineering Roadmap](./dbt_platform_engineering_roadmap.md)

This repository contains a complete 4-week dbt Platform Engineering curriculum, hands-on practice projects, and production blueprints covering multi-engine data warehouses (DuckDB, AWS Redshift), incremental optimization, SCD Type 2 snapshots, Astronomer Cosmos Airflow orchestration, Slim CI state deferral, and platform governance.

---

## Repository Structure

```text
learn-dbt/
├── dbt_platform_engineering_roadmap.md    # 4-Week master curriculum, notes, and interview battlecard
├── README.md                              # This getting-started guide
└── practice/                              # Hands-on projects & shared virtual environment
    ├── venv/                              # Shared Python 3.12 virtual environment (gitignored)
    ├── jaffle_shop/                       # Week 1: Multi-Engine DX & Foundational Architecture
    │   ├── dbt_project.yml
    │   ├── packages.yml
    │   ├── seeds/                         # Raw CSV seeds (customers, orders, items, products, stores, supplies)
    │   ├── models/
    │   │   ├── staging/                   # Cleaned views, schema tests, source declarations
    │   │   └── marts/                     # Dimension & fact tables, business logic
    │   ├── macros/                        # Cross-adapter macros (cents_to_dollars)
    │   └── README.md
    │
    ├── week2_advanced_incrementals/       # Week 2: Incrementals, Redshift Optimization & Snapshots
    │   ├── dbt_project.yml
    │   ├── packages.yml
    │   ├── profiles.yml                   # Multi-target profile (dev_local DuckDB, dev_redshift)
    │   ├── seeds/                         # Raw streaming datasets (customers_w2, orders_w2)
    │   ├── models/
    │   │   ├── staging/                   # Source SLAs & freshness, stg models
    │   │   └── marts/                     # Optimized incremental fact model (delete+insert, sort/dist keys)
    │   ├── snapshots/                     # SCD Type 2 historical snapshot (snap_customers)
    │   └── README.md
    │
    ├── week3_orchestration_and_ci/        # Week 3: Airflow Cosmos & Slim CI/CD State Deferral
    │   ├── dbt_project/                   # 3-layer dbt project (staging, intermediate, marts)
    │   ├── airflow/                       # Standalone Docker Airflow + Astronomer Cosmos DAGs
    │   ├── ci_cd/                         # Local Slim CI state deferral runner & state artifacts
    │   ├── quality/                       # SQLFluff & pre-commit configuration
    │   ├── run_all_checks.sh              # 1-command verification suite
    │   └── README.md
    │
    └── week4_mesh_and_contracts/          # Week 4: dbt Mesh, Model Contracts & Legacy Migration
        ├── finance_platform/              # Domain project: public contract-enforced fct_revenue
        ├── marketing_analytics/           # Domain project: cross-project consumer
        ├── run_all_checks.sh              # 1-command verification suite
        └── README.md
```

---

## 1. Local Python Environment Setup

The projects use **Python 3.12** with `dbt-core~=1.8.0`, `dbt-duckdb~=1.8.0`, `pre-commit`, and `sqlfluff`.

```bash
# Navigate to the practice directory
cd practice

# Create virtual environment (Python 3.12 recommended)
python3.12 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Upgrade pip and install core dependencies
pip install --upgrade pip
pip install "dbt-core~=1.8.0" "dbt-duckdb~=1.8.0" pre-commit sqlfluff sqlfluff-templater-dbt
```

---

## 2. Quickstart & Practice Projects

### Week 1: Multi-Engine Foundations (`practice/jaffle_shop`)

Learn layered architecture (Staging / Marts), cross-adapter macros, data tests, and unit tests using DuckDB.

```bash
cd practice/jaffle_shop

# Install package dependencies (dbt_utils)
dbt deps

# Seed raw tables, build models, and run tests in one command
dbt build
```

---

### Week 2: Advanced Incrementals & Snapshots (`practice/week2_advanced_incrementals`)

Learn `delete+insert` incremental strategies, Redshift distkey/sortkey optimization, lookback window buffering, and SCD Type 2 change tracking snapshots.

```bash
cd practice/week2_advanced_incrementals

# Run locally on DuckDB
dbt seed --target dev_local
dbt build --target dev_local

# Or run against AWS Redshift (requires REDSHIFT_* env vars)
dbt seed --target dev_redshift
dbt build --target dev_redshift
```

---

### Week 3: Airflow Cosmos & Slim CI/CD (`practice/week3_orchestration_and_ci`)

Learn Astronomer Cosmos dynamic DAG generation, Slim CI manifest state deferral (`--select state:modified+ --defer`), and pre-commit linting.

```bash
cd practice/week3_orchestration_and_ci
source ../venv/bin/activate

# Run the complete end-to-end automated verification suite
./run_all_checks.sh
```

---

### Week 4: Enterprise Scale — dbt Mesh, Contracts & Migration (`practice/week4_mesh_and_contracts`)

Learn dbt Mesh multi-project architecture, enforced model contracts, model versioning for zero-downtime breaking changes, and migrating legacy stored procedures to modular dbt DAGs.

Two projects are included:
- **`finance_platform/`** — publishes `fct_revenue` as a public, contract-enforced model
- **`marketing_analytics/`** — consumes `fct_revenue` via cross-project reference

```bash
cd practice/week4_mesh_and_contracts
source ../venv/bin/activate

# Run both projects end-to-end
./run_all_checks.sh

# Or run each project individually:
cd finance_platform && export DBT_PROFILES_DIR="$(pwd)"
dbt deps && dbt seed --target dev_local && dbt build --target dev_local

# Try breaking the contract (demonstrates compile-time enforcement):
# Edit models/marts/fct_revenue.sql — rename net_revenue_usd to anything else
# Then: dbt run --select fct_revenue --target dev_local
# Expected: Contract violation error before any SQL runs
```

---

## 3. Curriculum Reference

For the full 4-week architectural roadmap, deep-dive technical notes, and Principal Data Platform Engineer interview battlecard, see:
👉 [dbt Platform Engineering Roadmap](./dbt_platform_engineering_roadmap.md)
