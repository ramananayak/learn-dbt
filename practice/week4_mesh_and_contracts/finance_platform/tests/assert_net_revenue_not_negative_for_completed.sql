-- tests/assert_net_revenue_not_negative_for_completed.sql
-- Asserts that no customer-day has negative net_revenue_usd when
-- the underlying transactions are all completed (no refunds).
-- A negative net on an all-completed day means a data pipeline bug.
--
-- Returns rows that FAIL the assertion (dbt test passes when 0 rows returned).

select
    r.customer_id,
    r.transaction_date,
    r.net_revenue_usd,
    r.refund_count
from {{ ref('fct_revenue') }} r
where r.net_revenue_usd < 0
  and r.refund_count = 0
