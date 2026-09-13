# dbt Platform Engineering Master Plan (4-Week Intensive)

**Target Role:** Senior role  
**Core Technologies:** dbt-core, AWS Redshift, DuckDB, Apache Airflow (Astronomer Cosmos), GitHub Actions, Snowflake (Trial)  
**Time Commitment:** 1 Month (~10–15 hours/week)

---

## 1. Environment Strategy: Docker vs. Local Setup

### Recommendation: Hybrid Setup (Industry Standard DX)

- **Weeks 1, 2, and 4 (dbt Development & Cloud Warehouses):** **Local Python Virtual Environment (`venv` or `uv`)**
  - _Why:_ Instant CLI feedback, seamless IDE/LSP auto-completion, direct file access to DuckDB files, and no container mount overhead.
- **Week 3 (Airflow Orchestration with Cosmos):** **Docker via Astro CLI**
  - _Why:_ Running Airflow natively on macOS/Linux requires managing Celery/Postgres backends, pathing, and environment conflicts. Astro CLI containerizes Airflow cleanly and mounts your local dbt directory automatically in one command (`astro dev start`).

---

## 2. 4-Week Curriculum & Hands-on Roadmap

```
Week 1: Multi-Engine DX, Profiles & Foundational Architecture
├── Multi-target profiles.yml (DuckDB local vs Redshift / Snowflake)
├── Layered project layout (Staging / Intermediate / Marts)
└── Cross-database macros, dbt-utils, and schema tests

Week 2: Advanced Incrementals, Redshift Optimization & Snapshots
├── Source definitions (__sources.yml / src_*.yml) with freshness & testing
├── Incremental strategies: Redshift (delete+insert) vs Snowflake (merge)
├── Warehouse tuning: Dist/Sort keys, clustering, microbatching
└── SCD Type 2 tracking with dbt Snapshots (strategy: timestamp / check)

Week 3: Production Orchestration (Airflow/Cosmos) & Slim CI/CD
├── Astronomer Cosmos integration for dynamic DAG generation
├── Slim CI with manifest deferral (dbt build --select state:modified+)
└── Platform hygiene: sqlfluff & dbt-checkpoint pre-commit hooks

Week 4: Enterprise Scale (dbt Mesh, Contracts), Migrations & System Design
├── dbt Mesh: Multi-project architecture, public models, cross-project refs
├── Model contracts & schema enforcement (contract: {enforced: true})
└── Legacy migration playbook: Stored procedures to modular dbt DAGs
```

---

### Week 1: Multi-Engine DX, Profiles & Foundational Architecture

#### Focus

Build an enterprise-grade developer setup where local development runs on DuckDB without incurring warehouse costs, while staging/prod seamlessly target AWS Redshift or Snowflake.

#### Key Resources

- [dbt Documentation: Connection Profiles (`profiles.yml`)](https://docs.getdbt.com/docs/core/connect-data-platform/connection-profiles)
- [dbt-duckdb GitHub Repository](https://github.com/duckdb/dbt-duckdb)
- [dbt Labs: How We Structure Our Projects](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview)

#### Practical Configuration & Code

**1. Multi-Target `profiles.yml` (`~/.dbt/profiles.yml`):**

```yaml
platform_dbt_project:
  target: "{{ env_var('DBT_TARGET', 'dev_local') }}"
  outputs:
    dev_local:
      type: duckdb
      path: ./dev_analytics.duckdb
      schema: main
      threads: 4

    dev_redshift:
      type: redshift
      host: "{{ env_var('REDSHIFT_HOST') }}"
      user: "{{ env_var('REDSHIFT_USER') }}"
      pass: "{{ env_var('REDSHIFT_PASSWORD') }}"
      port: 5439
      dbname: dev
      schema: "dbt_{{ env_var('USER') }}"
      threads: 4

    dev_snowflake:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('SNOWFLAKE_USER') }}"
      password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
      role: transformer
      database: dev_db
      warehouse: dev_wh
      schema: "dbt_{{ env_var('USER') }}"
      threads: 4
```

**2. Staging Model (`models/staging/stg_orders.sql`):**

```sql
with source as (
    select * from {{ source('raw_data', 'orders') }}
),
renamed as (
    select
        cast(id as {{ dbt.type_string() }}) as order_id,
        cast(user_id as {{ dbt.type_string() }}) as customer_id,
        cast(order_date as date) as order_date,
        cast(status as {{ dbt.type_string() }}) as order_status,
        cast(amount as {{ dbt.type_numeric() }}) as gross_amount_usd,
        cast(updated_at as {{ dbt.type_timestamp() }}) as updated_at
    from source
)
select * from renamed
```

---

### Week 2: Advanced Incrementals, Redshift Optimization & Snapshots

#### Focus

Master source declaration, incremental loading models, warehouse-level pushdown optimizations (distribution and sort keys on Redshift), and historical change capture (SCD Type 2).

#### Key Resources

- [dbt Documentation: Sources](https://docs.getdbt.com/docs/build/sources)
- [dbt Documentation: Incremental Models & Strategies](https://docs.getdbt.com/docs/build/incremental-models)
- [AWS Redshift Best Practices for dbt Performance](https://aws.amazon.com/blogs/big-data/best-practices-for-using-dbt-with-amazon-redshift/)
- [dbt Documentation: Snapshots (SCD Type 2)](https://docs.getdbt.com/docs/build/snapshots)

#### Practical Configuration & Code

**1. Source Definition (`models/staging/src_raw_data.yml`):**

```yaml
version: 2

sources:
  - name: raw_data
    schema: "{{ target.schema }}_raw"
    tables:
      - name: orders
        identifier: raw_orders
        config:
          loaded_at_field: updated_at
          freshness:
            warn_after: { count: 12, period: hour }
            error_after: { count: 24, period: hour }
      - name: customers
        identifier: raw_customers
```

**2. Optimized Incremental Model (`models/marts/fct_daily_customer_orders.sql`):**

```sql
{{
    config(
        materialized = 'incremental',
        unique_key = 'customer_order_key',
        incremental_strategy = 'delete+insert',
        sortkey = 'order_date',
        distkey = 'customer_id',
        on_schema_change = 'append_new_columns'
    )
}}

with orders as (
    select * from {{ ref('stg_orders') }}
    {% if is_incremental() %}
        -- Lookback buffer to safely capture late-arriving updates
        where order_date >= (select coalesce(dateadd(day, -3, max(order_date)), '1970-01-01') from {{ this }})
    {% endif %}
),

aggregated as (
    select
        {{ dbt_utils.generate_surrogate_key(['customer_id', 'order_date']) }} as customer_order_key,
        customer_id,
        order_date,
        count(order_id) as total_orders,
        sum(gross_amount_usd) as total_revenue_usd,
        max(updated_at) as last_updated_at
    from orders
    group by 1, 2, 3
)

select * from aggregated
```

**3. SCD Type 2 Snapshot (`snapshots/snap_customers.sql`):**

```sql
{% snapshot snap_customers %}

{{
    config(
      target_schema='snapshots',
      unique_key='customer_id',
      strategy='timestamp',
      updated_at='updated_at',
      invalidate_hard_deletes=True
    )
}}

select
    customer_id,
    customer_name,
    email,
    subscription_status,
    updated_at
from {{ ref('stg_customers') }}

{% endsnapshot %}
```

---

### Week 3: Production Orchestration (Airflow/Cosmos) & Slim CI/CD

#### Focus

Deploy dbt inside Apache Airflow without monolithic Bash operators, and build automated GitHub Actions workflows using Slim CI and state deferral.

#### Key Resources

- [Astronomer Cosmos Documentation](https://astronomer.github.io/astronomer-cosmos/)
- [dbt Documentation: Slim CI & State Deferral](https://docs.getdbt.com/docs/deploy/continuous-integration)
- [pre-commit / dbt-checkpoint Repository](https://github.com/dbt-checkpoint/dbt-checkpoint)

#### Practical Configuration & Code

**1. Airflow Orchestration DAG via Cosmos (`dags/dbt_platform_dag.py`):**

```python
from datetime import datetime
from pathlib import Path
from airflow.decorators import dag
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig
from cosmos.profiles import RedshiftUserPasswordProfileMapping

DEFAULT_DBT_ROOT = Path("/usr/local/airflow/dbt")

profile_config = ProfileConfig(
    profile_name="platform_dbt_project",
    target_name="dev_redshift",
    profile_mapping=RedshiftUserPasswordProfileMapping(
        conn_id="redshift_default",
        profile_args={"schema": "dbt_rnayak"},
    ),
)

@dag(
    schedule_interval="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["dbt", "platform"],
)
def dbt_analytics_dag():
    dbt_models = DbtTaskGroup(
        group_id="transform_core",
        project_config=ProjectConfig(DEFAULT_DBT_ROOT / "core_project"),
        profile_config=profile_config,
        execution_config=ExecutionConfig(dbt_executable_path="/usr/local/bin/dbt"),
    )

dbt_analytics_dag()
```

**2. GitHub Actions Slim CI Workflow (`.github/workflows/dbt_slim_ci.yml`):**

```yaml
name: dbt-slim-ci
on:
  pull_request:
    branches: [main]

jobs:
  ci-check:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Install dbt & Dependencies
        run: |
          pip install dbt-redshift dbt-duckdb
          dbt deps

      - name: Fetch Production State Manifest
        run: |
          mkdir -p state_artifacts
          aws s3 cp s3://company-dbt-metadata/production/manifest.json ./state_artifacts/manifest.json

      - name: Run Modified Models & Downstream Tests (Slim CI)
        env:
          DBT_TARGET: dev_redshift
          REDSHIFT_HOST: ${{ secrets.REDSHIFT_HOST }}
          REDSHIFT_USER: ${{ secrets.REDSHIFT_USER }}
          REDSHIFT_PASSWORD: ${{ secrets.REDSHIFT_PASSWORD }}
        run: |
          dbt build \
            --select state:modified+ \
            --defer \
            --state ./state_artifacts \
            --target dev_redshift
```

---

### Week 4: Enterprise Scale (dbt Mesh, Contracts), Migrations & System Design

#### Focus

Design decentralized dbt Mesh architectures, enforce model contracts for API stability, execute zero-drift migrations from legacy SQL stored procedures, and manage breaking schema changes with model versioning.

#### Key Resources

- [dbt Documentation: dbt Mesh & Multi-Project Deployments](https://docs.getdbt.com/docs/mesh/about-mesh)
- [dbt Documentation: Model Contracts](https://docs.getdbt.com/docs/collaborate/govern/model-contracts)
- [dbt Documentation: Model Versioning](https://docs.getdbt.com/docs/collaborate/govern/model-versions)
- [Refactoring Legacy SQL to dbt (Step-by-Step Guide)](https://docs.getdbt.com/guides/refactoring-legacy-sql)
- [dbt-audit-helper Package](https://hub.getdbt.com/dbt-labs/audit_helper/latest/)

#### Hands-on Practice

See `practice/week4_mesh_and_contracts/` for the full working project. Run:

```bash
cd practice/week4_mesh_and_contracts
source ../venv/bin/activate
./run_all_checks.sh
```

Two projects are included:
- **`finance_platform/`** — owns revenue data; publishes `fct_revenue` as a public, contract-enforced model
- **`marketing_analytics/`** — consumes `fct_revenue` via cross-project reference; joins with segment data

#### Practical Configuration & Code

**1. Public Contract-Enforced Model (`finance_platform/models/marts/fct_revenue.yml`):**

```yaml
version: 2

models:
  - name: fct_revenue
    description: "Governed daily revenue fact. Public model — accessible to all dbt Mesh projects."
    access: public
    config:
      contract:
        enforced: true
    columns:
      - name: revenue_key
        data_type: varchar
        description: "Surrogate primary key on (customer_id, transaction_date)."
        constraints:
          - type: not_null
          - type: primary_key
        tests: [not_null, unique]
      - name: customer_id
        data_type: varchar
        constraints:
          - type: not_null
      - name: transaction_date
        data_type: date
        constraints:
          - type: not_null
      - name: net_revenue_usd
        data_type: double
        constraints:
          - type: not_null
      - name: refund_count
        data_type: bigint
        constraints:
          - type: not_null
      - name: last_updated_at
        data_type: timestamp
        constraints:
          - type: not_null
```

**What enforced contracts do:** If `fct_revenue.sql` is edited to rename `net_revenue_usd` to anything else, `dbt run` fails at compile time with:
```
Contract violation in model fct_revenue:
  column 'net_revenue_usd' declared in contract but not found in model SQL
```
This prevents silent schema drift from breaking downstream consumers.

**2. Model Versioning — Zero-Downtime Breaking Changes:**

When a column rename is required, deploy both versions simultaneously:

```sql
-- models/marts/fct_revenue_v1.sql  (deprecated — remove after 2026-10-01)
select
    revenue_key, customer_id, transaction_date,
    net_revenue_usd,        -- old column name
    ...
from {{ ref('int_daily_revenue') }}
```

```sql
-- models/marts/fct_revenue_v2.sql  (current)
select
    revenue_key, customer_id, transaction_date,
    net_revenue_usd as net_amount_usd,   -- renamed
    round(cast(refund_count as double) / transaction_count, 4) as refund_rate,  -- new
    ...
from {{ ref('int_daily_revenue') }}
```

Both have `access: public` and `contract: enforced: true`. Downstream consumers migrate from v1 to v2 on their own timeline. Drop v1 after the deprecation window.

**3. Cross-Project Reference (`marketing_analytics/models/marts/dim_customer_revenue_by_segment.sql`):**

```sql
-- In production Mesh (multi-project deployment):
with revenue as (
    -- Cross-project ref: finance_platform project, fct_revenue public model
    select * from {{ ref('finance_platform', 'fct_revenue') }}
),
segments as (
    select * from {{ ref('stg_customer_segments') }}
)
select
    r.transaction_date,
    r.customer_id,
    s.segment,
    s.acquisition_channel,
    r.net_revenue_usd
from revenue r
left join segments s on r.customer_id = s.customer_id
```

The marketing team gets revenue data without owning the revenue pipeline. The finance team can refactor staging and intermediate models freely — the contract on `fct_revenue` is the only interface that matters.

**4. Legacy Migration Reconciliation (`finance_platform/analysis/compare_legacy_vs_dbt.sql`):**

```sql
with legacy as (
    select customer_id, revenue_date as transaction_date,
           total_revenue_usd as net_revenue_usd, transaction_count
    from {{ ref('legacy_revenue_summary') }}
),
dbt_mart as (
    select customer_id, transaction_date, net_revenue_usd, transaction_count
    from {{ ref('fct_revenue') }}
)
select 'in_legacy_only' as match_status, count(*) as row_count
from legacy l left join dbt_mart d
    on l.customer_id = d.customer_id and l.transaction_date = d.transaction_date
where d.customer_id is null
union all
select 'in_dbt_only', count(*)
from dbt_mart d left join legacy l
    on d.customer_id = l.customer_id and d.transaction_date = l.transaction_date
where l.customer_id is null
union all
select 'in_both', count(*)
from legacy l inner join dbt_mart d
    on l.customer_id = d.customer_id and l.transaction_date = d.transaction_date
union all
select 'value_discrepancies', count(*)
from legacy l inner join dbt_mart d
    on l.customer_id = d.customer_id and l.transaction_date = d.transaction_date
where abs(l.net_revenue_usd - d.net_revenue_usd) > 0.01
```

Target before cutover: `in_both = 100%`, `in_legacy_only = 0`, `value_discrepancies = 0`.

**Migration steps:**
1. Seed legacy ETL output alongside raw data
2. Build dbt models
3. Run reconciliation — investigate any discrepancies
4. Deploy dbt models to production, disable the stored proc
5. Monitor for one week before removing legacy code

**5. Singular Test — Business Invariant (`tests/assert_net_revenue_not_negative_for_completed.sql`):**

```sql
-- Returns rows that FAIL (dbt test passes when 0 rows returned)
select customer_id, transaction_date, net_revenue_usd, refund_count
from {{ ref('fct_revenue') }}
where net_revenue_usd < 0
  and refund_count = 0
```

If a customer-day has negative net revenue but zero refunds, something is wrong in the pipeline.

---

## 3. High-Signal Reference Resources

- **Official Courses & Certifications:**
  - [dbt Learn (Free On-demand Courses)](https://learn.getdbt.com/): _dbt Fundamentals_, _Advanced Materializations_, _dbt Mesh_.
  - _dbt Analytics Engineering Certification Exam Guide_.
- **Open Source Blueprints & Architecture:**
  - [GitLab Data Team Public Analytics Project](https://gitlab.com/gitlab-data/analytics): Production standard for repository structure, macros, and CI pipelines.
- **Community:**
  - dbt Community Slack channels: `#advice-dbt-for-enterprises`, `#tools-airflow`, `#db-redshift`.

---

## 4. Principal Interview Battlecard

| Scenario / Question | Winning Platform Engineering Response |
| :--- | :--- |
| **Monolith vs Mesh**<br>_"Our single dbt repo has 3,000 models and CI takes 50 minutes. How do you fix it?"_ | Deconstruct into domain-owned repositories via **dbt Mesh**. Define `public` models with **enforced contracts**, keep internal transformations `private`, and enforce **Slim CI with state deferral** (`--select state:modified+ --defer`) so CI only runs changed models. Each domain team owns their CI pipeline independently. |
| **Incremental Performance**<br>_"An incremental model on Redshift is running slower than a full rebuild. What is wrong?"_ | Check `distkey` and `sortkey` alignment with the `unique_key` and incremental filter column. If the `distkey` is misaligned, Redshift performs expensive cross-node data redistribution during the `delete+insert` merge step. Also verify table vacuum status (`VACUUM SORT ONLY`) and ANALYZE stats — stale stats cause the query planner to choose full scans. |
| **Zero-Downtime Deployments**<br>_"How do you deploy a breaking column rename on a public model safely?"_ | Deploy both versions simultaneously: `fct_revenue_v1` (old name, marked deprecated) and `fct_revenue_v2` (new name). Both have `access: public` and `contract: enforced: true`. Notify downstream consumers, give them a sprint to migrate their `ref()` calls. After the deprecation window, drop v1. Never rename in-place on a public model. |
| **Airflow Orchestration**<br>_"Why use Cosmos over a standard Airflow BashOperator for dbt?"_ | `BashOperator('dbt run')` is a black box — one Airflow task, no model-level visibility, and a single failure reruns the entire pipeline. Cosmos generates one Airflow task per dbt node (model + test), so you get individual retries on transient failures, parallel execution across disjoint DAG branches, and test-after-model execution. Lineage is also visible in the Airflow UI. |
| **Contract Violation**<br>_"A downstream team says your model broke their pipeline. How do you prevent this?"_ | Enforce `contract: enforced: true` on all public models. This makes the column schema a compile-time guarantee — any SQL change that drops or renames a declared column fails before touching the warehouse. Pair with model versioning: breaking changes get a new version (`v2`) deployed alongside the old one, not in-place. |
| **Source Freshness**<br>_"How do you detect that an upstream data feed stopped loading?"_ | Declare `loaded_at_field` and `freshness` thresholds in the source YAML. Run `dbt source freshness` in CI or on a schedule. dbt queries `MAX(loaded_at_field)` and compares against `warn_after` / `error_after` thresholds. Failed freshness checks block downstream model runs, surfacing the issue before stale data propagates to marts. |
| **Late-Arriving Data**<br>_"Your incremental model is missing orders that arrive with yesterday's date. Why?"_ | The incremental filter `where order_date >= max(order_date)` only processes today's data. Late-arriving records with yesterday's date are silently skipped. Fix: use a lookback buffer — `where order_date >= dateadd(day, -3, max(order_date))`. The `delete+insert` strategy re-processes and replaces any existing rows in the lookback window, so there's no double-counting. |
| **Schema Migration**<br>_"How do you add a NOT NULL column to a model that already has millions of rows in production?"_ | Use `on_schema_change: 'append_new_columns'` for backward-compatible additions. For NOT NULL columns: first add the column as nullable, backfill the data in a separate migration step, then add the NOT NULL constraint in a follow-up deploy. Never add a NOT NULL column with no default in a single deploy — it will fail on existing rows. |
| **Testing Strategy**<br>_"What tests do you put on a mart model before it goes to production?"_ | At minimum: `not_null` + `unique` on the primary key, `not_null` on all foreign keys, `accepted_values` on status/enum columns. For financial models: a singular test asserting business invariants (e.g. net revenue ≥ 0 when no refunds). For incremental models: a row count test comparing the incremental run against a full rebuild on a sample date range. |
| **CI Cost**<br>_"Our dbt CI runs cost $800/month in warehouse compute. How do you cut that?"_ | Three levers: (1) **Slim CI** — `--select state:modified+ --defer` runs only changed models and defers unmodified upstream refs to production, cutting nodes built by 60–80%. (2) **DuckDB for CI** — run unit tests and schema validation against DuckDB (zero cost) and only run integration tests against Redshift on merge to main. (3) **Concurrency** — increase `threads` and use a dedicated CI warehouse with auto-pause. |
| **Data Lineage**<br>_"A business analyst says a revenue number changed. How do you trace it?"_ | Start with `dbt docs generate` + `dbt docs serve` to visualize the lineage graph. Trace upstream from the mart to the source. Check `dbt run_results.json` for the last successful run timestamps. Use `dbt source freshness` to verify the source loaded. If the model is incremental, check whether the lookback window captured the relevant date range. |
| **Multi-Warehouse Strategy**<br>_"We're migrating from Redshift to Snowflake. How do you manage dbt during the transition?"_ | Add a `dev_snowflake` target to `profiles.yml`. Use cross-database macros (`dbt.type_string()`, `dbt.type_numeric()`) and dispatch macros for any warehouse-specific SQL. Run both targets in parallel during migration. Use `audit_helper.compare_relations()` to verify row-for-row parity between Redshift and Snowflake outputs before cutting over. |

