# Week 3: Production Orchestration (Airflow / Astronomer Cosmos) & Slim CI/CD

Welcome to **Week 3** of the dbt Platform Engineering curriculum. This module focuses on two pillars of enterprise data platform engineering:

1. **Dynamic Pipeline Orchestration with Apache Airflow & Astronomer Cosmos**: Moving away from monolithic `BashOperator` execution to granular, task-level DAG generation with individual model retries, test-after-model execution, and pipeline lineage.
2. **Slim CI with Manifest State Deferral**: Slashing CI runtime and cloud warehouse spend by comparing modified pull request code against the production `manifest.json` (`state:modified+`) and deferring unmodified upstream dependencies (`--defer`).
3. **Platform Hygiene & Governance**: Automated code quality gates using `sqlfluff` and `dbt-checkpoint` pre-commit hooks.

---

## 1. Architecture Overview

```
                      ┌─────────────────────────────────────────────────────────┐
                      │              Astronomer Cosmos Dynamic DAG              │
                      │                                                         │
   [raw_customers] ───► [stg_customers] ──────────────────────────┐             │
                                                                  ▼             │
                                                          [dim_customers]       │
                                                                  ▲             │
   [raw_orders]    ───► [stg_orders] ──► [int_customer_summary] ──┘             │
                              │                                                 │
                              └────────► [fct_daily_sales]                      │
                      └─────────────────────────────────────────────────────────┘

                      ┌─────────────────────────────────────────────────────────┐
                      │                 dbt Slim CI & State Deferral            │
                      │                                                         │
                      │  Production Manifest (S3 / Baseline State)              │
                      │       │                                                 │
                      │       ▼  (Compare Checksums)                            │
                      │  Developer PR modifies: [stg_orders]                    │
                      │       │                                                 │
                      │       ├── [raw_customers, raw_orders] ──> SKIPPED       │
                      │       ├── [stg_customers] ──────────────> DEFERRED      │
                      │       └── [stg_orders, int_summary,                     │
                      │            dim_customers, fct_sales] ───> BUILT & TESTED│
                      └─────────────────────────────────────────────────────────┘
```

---

## 2. Directory Layout

```text
practice/week3_orchestration_and_ci/
├── README.md                                  # Complete master guide
├── run_all_checks.sh                          # End-to-end local validation script
├── dbt_project/                               # Multi-layer sample dbt project
│   ├── dbt_project.yml
│   ├── packages.yml
│   ├── profiles.yml                           # Multi-target profile (dev_local, dev_redshift, ci)
│   ├── seeds/
│   │   ├── raw_customers.csv
│   │   └── raw_orders.csv
│   ├── models/
│   │   ├── staging/
│   │   │   ├── src_raw_data.yml
│   │   │   ├── stg_customers.sql
│   │   │   ├── stg_orders.sql
│   │   │   └── stg_models.yml
│   │   ├── intermediate/
│   │   │   ├── int_customer_order_summary.sql
│   │   │   └── int_models.yml
│   │   └── marts/
│   │       ├── dim_customers.sql
│   │       ├── fct_daily_sales.sql
│   │       └── marts_models.yml
│   └── tests/
│       └── assert_total_revenue_positive.sql
├── airflow/                                   # Lightweight Apache Airflow orchestration
│   ├── Dockerfile                             # Lightweight Airflow + Cosmos image
│   ├── docker-compose.yml                     # Single-container standalone Airflow service
│   ├── requirements.txt                       # astronomer-cosmos, dbt-duckdb, dbt-redshift
│   ├── run_airflow.sh                         # 1-command startup/stop/log helper
│   └── dags/
│       ├── dbt_cosmos_dag.py                  # Local DuckDB dynamic Cosmos DAG
│       └── dbt_cosmos_redshift_dag.py         # Production Redshift Cosmos DAG
├── ci_cd/                                     # Slim CI / CD & State Deferral resources
│   ├── run_slim_ci_local.sh                   # Self-contained local Slim CI test runner
│   ├── simulate_slim_ci.py                    # Lineage inspector & state explainer
│   └── .github/
│       └── workflows/
│           └── dbt_slim_ci.yml                # Production GitHub Actions workflow
└── quality/                                   # Platform hygiene & linting
    ├── .pre-commit-config.yaml                # Pre-commit configuration
    └── .sqlfluff                              # Production SQLFluff rules for dbt
```

---

## 3. Python 3.12 Environment Setup

This project uses **Python 3.12** for stability with `dbt-core~=1.8.0`, `dbt-duckdb~=1.8.0`, `sqlfluff`, and `pre-commit` / `dbt-checkpoint`.

```bash
# Navigate to project directory
cd practice/week3_orchestration_and_ci

# Create virtual environment using Python 3.12 (if not created in practice/venv)
python3.12 -m venv ../venv

# Activate virtual environment
source ../venv/bin/activate

# Upgrade pip and install core dependencies
pip install --upgrade pip
pip install "dbt-core~=1.8.0" "dbt-duckdb~=1.8.0" pre-commit sqlfluff sqlfluff-templater-dbt
```

---

## 4. Part 1: Hands-on dbt Project

The included sample project (`dbt_project/`) implements a production-grade 3-layer architecture:

- **Seeds (`seeds/`)**: `raw_customers` and `raw_orders` loaded into schema `main_raw`.
- **Staging (`models/staging/`)**: `stg_customers` and `stg_orders` with type casting, string cleaning, currency conversion, and schema tests.
- **Intermediate (`models/intermediate/`)**: `int_customer_order_summary` aggregating customer order rollups.
- **Marts (`models/marts/`)**: `dim_customers` (with customer loyalty tiers) and `fct_daily_sales` (daily revenue KPIs).
- **Singular Tests (`tests/`)**: `assert_total_revenue_positive.sql`.

### Run Locally with DuckDB:

```bash
# Activate your python venv
source ../venv/bin/activate

# Set profile path and build project
export DBT_PROFILES_DIR="$(pwd)/dbt_project"
cd dbt_project

dbt seed --target dev_local
dbt build --target dev_local
```

**Output:**

```text
Processed: 5 models | 31 tests | 2 seeds
Summary: 38 total | 38 success
```

---

## 5. Part 2: Lightweight Airflow + Astronomer Cosmos

### Why Astronomer Cosmos over `BashOperator`?

| Feature              | Legacy `BashOperator('dbt run')`         | Astronomer Cosmos (`DbtTaskGroup`)                                                  |
| :------------------- | :--------------------------------------- | :---------------------------------------------------------------------------------- |
| **Visibility**       | 1 monolithic black-box Airflow task      | Individual tasks per model, seed, and test in Airflow UI                            |
| **Failures**         | Entire DAG fails; must rerun everything  | Retry only the failed model/test node                                               |
| **Concurrency**      | Single thread/process runner bottleneck  | Disjoint DAG branches execute in parallel on Airflow workers                        |
| **Test Integration** | Tests run at end after all models finish | Test runs immediately after its specific model finishes (`TestBehavior.AFTER_EACH`) |

### Production Container Architecture & Dependency Isolation

To prevent dependency conflicts between Apache Airflow's 200+ pinned packages and dbt adapter libraries, the Docker setup uses **virtual environment isolation**:
- **Airflow Environment**: Hosts `apache-airflow:2.9.3` and `astronomer-cosmos`.
- **dbt Virtualenv (`/opt/airflow/dbt_venv`)**: Hosts `dbt-core`, `dbt-duckdb`, and `dbt-redshift` isolated from Airflow core.
- **OS Dependencies**: `libpq-dev` and `build-essential` are pre-installed for `psycopg2` compilation.
- **Cosmos Execution Config**: DAGs invoke dbt via `ExecutionConfig(dbt_executable_path="/opt/airflow/dbt_venv/bin/dbt")`.

### Starting Airflow (Lightweight Standalone Docker Setup)

We provide a zero-configuration, single-container standalone Airflow setup with Astronomer Cosmos pre-installed:

```bash
cd airflow

# Start Airflow in background (auto-initializes admin/admin credentials)
./run_airflow.sh start
```

- **Airflow Web UI**: [http://localhost:8080](http://localhost:8080)
- **Username**: `admin`
- **Password**: `admin`

### Airflow Helper Commands:

```bash
./run_airflow.sh status    # Check container status
./run_airflow.sh logs      # Tail live Airflow logs
./run_airflow.sh test      # Trigger a CLI test run of dbt_cosmos_duckdb_pipeline
./run_airflow.sh stop      # Stop and tear down Airflow
```

---

## 6. Part 3: Slim CI & State Deferral

### FAQ: _"Do I need to push the code to a repo to run Slim CI?"_

> **No, you do NOT need to push to a remote repository to test or run Slim CI.**

Slim CI is powered by two dbt flags:

1. `--state <path>`: Points dbt to a baseline `manifest.json` (representing the current "production" state).
2. `--defer`: Resolves unmodified upstream `ref()` dependencies against the baseline tables/views rather than building them locally.
3. `--select state:modified+`: Tells dbt to only build and test models whose code/config changed since the baseline, plus all downstream children (`+`).

### Local Execution vs Remote CI:

| Environment                    | How It Operates                                                                                                                                                                                                                                                                      |
| :----------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Local (Zero Push Required)** | 1. Generate baseline manifest (`manifest.json`) in `ci_cd/state_artifacts/`.<br>2. Edit any model locally.<br>3. Run `dbt build --select state:modified+ --defer --state ./state_artifacts`.<br>4. dbt compares against the baseline file on disk and runs only the modified models! |
| **Remote CI (GitHub Actions)** | 1. Developer opens a Pull Request.<br>2. CI runner downloads `manifest.json` from AWS S3.<br>3. CI runner executes `dbt build --select state:modified+ --defer --state ./state_artifacts` against an isolated PR schema (e.g. `dbt_ci_pr_42`).                                       |

### Running the Local Slim CI Demonstration Script:

We created an automated demonstration script `run_slim_ci_local.sh`:

```bash
source ../venv/bin/activate
./ci_cd/run_slim_ci_local.sh
```

**What the script executes:**

1. **Builds baseline**: Builds the full project (38 nodes: 2 seeds, 5 models, 31 tests) and exports `manifest.json` to `state_artifacts/`.
2. **Simulates a developer change**: Adds a column to `models/staging/stg_orders.sql`.
3. **Runs Slim CI**: Runs `dbt build --select state:modified+ --defer --state state_artifacts`.
4. **Demonstrates savings**:
   - `raw_customers`, `raw_orders`, `stg_customers` and their 10 tests are **SKIPPED** and deferred.
   - Only `stg_orders` and downstream models (`int_customer_order_summary`, `dim_customers`, `fct_daily_sales`) and their tests are executed (25 nodes total vs 38).
5. **Clean restoration**: Automatically restores `stg_orders.sql` back to clean state.

---

## 7. Part 4: Platform Hygiene & Pre-commit Hooks

Ensure code governance and formatting before code reaches CI:

- **`.pre-commit-config.yaml`**: Configured with `sqlfluff` (DuckDB/Redshift dialect) and `dbt-checkpoint` (enforcing descriptions and minimum test counts).
- **`.sqlfluff`**: Configured with dbt templater and enterprise lowercase/explicit aliasing standards.

Install and run pre-commit locally:

```bash
# Ensure venv (Python 3.12) is active
source ../venv/bin/activate

# Run pre-commit across all files
pre-commit run --all-files --config quality/.pre-commit-config.yaml
```

---

## 8. Cross-Engine & Parser Compatibility Notes

- **Generic Test Argument Compatibility**: In `macros/test_accepted_values.sql`, test macros accept both `arguments: { values: [...] }` (enforced by `dbt-fusion 2.0+`) and legacy top-level test params (used by `dbt-core 1.8.x`), ensuring zero syntax failures across local CLI and Airflow.
- **Standalone Password Reset**: `airflow standalone` initializes an admin user. `./run_airflow.sh` automatically ensures `admin`/`admin` credentials are set upon startup.

---

## 9. Quick Verification

To verify all components (dbt project, Airflow Cosmos DAG syntax, and Slim CI state deferral) in a single run:

```bash
source ../venv/bin/activate
./run_all_checks.sh
```
