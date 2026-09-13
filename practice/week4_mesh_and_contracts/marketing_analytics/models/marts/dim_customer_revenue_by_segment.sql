-- dim_customer_revenue_by_segment.sql
--
-- dbt Mesh cross-project model.
--
-- In a real multi-project Mesh deployment this model would reference the
-- finance_platform project's public model using a cross-project ref:
--
--   {{ ref('finance_platform', 'fct_revenue') }}
--
-- For local DuckDB practice (single database), we reference the finance mart
-- directly. To simulate Mesh, run finance_platform first, then marketing_analytics
-- pointing at the same DuckDB file, or use the --defer flag with the finance
-- project's manifest as the state artifact.
--
-- Cross-project ref syntax (production Mesh):
--   from {{ ref('finance_platform', 'fct_revenue') }}

with revenue as (
    -- In Mesh: {{ ref('finance_platform', 'fct_revenue') }}
    -- Local simulation: read from the finance project's DuckDB output
    select * from {{ ref('fct_revenue') }}
),

segments as (
    select * from {{ ref('stg_customer_segments') }}
),

joined as (
    select
        r.transaction_date,
        r.customer_id,
        s.segment,
        s.acquisition_channel,
        s.cohort_month,
        r.transaction_count,
        r.gross_revenue_usd,
        r.refund_amount_usd,
        r.net_revenue_usd,
        r.refund_count
    from revenue r
    left join segments s on r.customer_id = s.customer_id
)

select * from joined
