with daily_revenue as (
    select * from {{ ref('int_daily_revenue') }}
)

select
    revenue_key,
    customer_id,
    transaction_date,
    transaction_count,
    refund_count,
    gross_revenue_usd,
    refund_amount_usd,
    net_revenue_usd,
    last_updated_at
from daily_revenue
