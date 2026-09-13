-- Singular test: daily gross revenue must never be negative
select
    order_date,
    gross_revenue_usd
from {{ ref('fct_daily_sales') }}
where gross_revenue_usd < 0
