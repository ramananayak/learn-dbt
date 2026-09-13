-- fct_revenue_v2.sql
-- Breaking change from v1: 'net_revenue_usd' renamed to 'net_amount_usd'.
-- Added: 'refund_rate' computed column.
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
    net_revenue_usd                                              as net_amount_usd,  -- renamed
    case
        when transaction_count > 0
        then round(cast(refund_count as double) / transaction_count, 4)
        else 0
    end                                                          as refund_rate,     -- new
    last_updated_at
from daily_revenue
