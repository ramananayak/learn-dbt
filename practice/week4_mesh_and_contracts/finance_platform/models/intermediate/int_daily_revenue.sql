with transactions as (
    select * from {{ ref('stg_transactions') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'transaction_date']) }} as revenue_key,
    customer_id,
    transaction_date,
    count(transaction_id)                                       as transaction_count,
    count(case when is_refund then 1 end)                       as refund_count,
    sum(case when not is_refund then amount_usd else 0 end)     as gross_revenue_usd,
    sum(case when is_refund then amount_usd else 0 end)         as refund_amount_usd,
    sum(amount_usd)                                             as net_revenue_usd,
    max(updated_at)                                             as last_updated_at
from transactions
group by 1, 2, 3
