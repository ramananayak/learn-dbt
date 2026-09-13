-- fct_revenue_v1.sql
-- DEPRECATED: Use fct_revenue_v2 — this version will be removed after 2026-10-01.
-- Breaking change: 'net_revenue_usd' renamed to 'net_amount_usd' in v2.
with daily_revenue as (
    select * from {{ ref('int_daily_revenue') }}
)

select
    revenue_key,
    customer_id,
    transaction_date,
    transaction_count,
    gross_revenue_usd,
    refund_amount_usd,
    net_revenue_usd,        -- old column name — kept for backward compatibility
    last_updated_at
from daily_revenue
