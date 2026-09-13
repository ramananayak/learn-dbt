-- analysis/compare_legacy_vs_dbt.sql
--
-- Migration reconciliation: compare the legacy stored-proc output
-- (seeded as legacy_revenue_summary) against the new dbt mart (fct_revenue).
--
-- Run with: dbt compile --select compare_legacy_vs_dbt
-- Then execute the compiled SQL in your warehouse / DuckDB client.
--
-- What to look for:
--   in_a_only  → rows in legacy but missing from dbt  (dbt is under-counting)
--   in_b_only  → rows in dbt but missing from legacy  (dbt found extra data)
--   in_both    → rows present in both (should be 100% of rows after migration)
--
-- Target: in_both = 100%, in_a_only = 0%, in_b_only = 0%

{% set legacy_relation = ref('legacy_revenue_summary') %}
{% set dbt_relation    = ref('fct_revenue') %}

with legacy as (
    select
        customer_id,
        revenue_date                as transaction_date,
        total_revenue_usd           as net_revenue_usd,
        transaction_count
    from {{ legacy_relation }}
),

dbt_mart as (
    select
        customer_id,
        transaction_date,
        net_revenue_usd,
        transaction_count
    from {{ dbt_relation }}
),

-- rows only in legacy
in_legacy_only as (
    select 'in_legacy_only' as source, l.*
    from legacy l
    left join dbt_mart d
        on l.customer_id = d.customer_id
       and l.transaction_date = d.transaction_date
    where d.customer_id is null
),

-- rows only in dbt
in_dbt_only as (
    select 'in_dbt_only' as source, d.customer_id, d.transaction_date, d.net_revenue_usd, d.transaction_count
    from dbt_mart d
    left join legacy l
        on d.customer_id = l.customer_id
       and d.transaction_date = l.transaction_date
    where l.customer_id is null
),

-- rows in both — check for value discrepancies
in_both as (
    select
        'in_both' as source,
        l.customer_id,
        l.transaction_date,
        l.net_revenue_usd       as legacy_net_revenue_usd,
        d.net_revenue_usd       as dbt_net_revenue_usd,
        l.net_revenue_usd - d.net_revenue_usd as revenue_diff,
        l.transaction_count     as legacy_count,
        d.transaction_count     as dbt_count
    from legacy l
    inner join dbt_mart d
        on l.customer_id = d.customer_id
       and l.transaction_date = d.transaction_date
)

-- Summary
select 'in_legacy_only' as match_status, count(*) as row_count from in_legacy_only
union all
select 'in_dbt_only',                    count(*) from in_dbt_only
union all
select 'in_both',                        count(*) from in_both
union all
select 'value_discrepancies',            count(*) from in_both where abs(revenue_diff) > 0.01
