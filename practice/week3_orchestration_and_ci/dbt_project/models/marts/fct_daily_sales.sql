with orders as (
    select * from {{ ref('stg_orders') }}
),

daily_metrics as (
    select
        order_date,
        count(distinct order_id) as total_orders,
        count(distinct customer_id) as total_ordering_customers,
        sum(case when order_status = 'completed' then order_amount_usd else 0 end) as gross_revenue_usd,
        sum(case when order_status = 'returned' then order_amount_usd else 0 end) as returned_amount_usd,
        sum(case when order_status = 'completed' then 1 else 0 end) as completed_orders_count
    from orders
    group by 1
)

select * from daily_metrics
