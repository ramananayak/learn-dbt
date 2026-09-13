with orders as (
    select * from {{ ref('stg_orders') }}
),

completed_orders as (
    select *
    from orders
    where order_status = 'completed'
),

customer_summary as (
    select
        customer_id,
        count(order_id) as total_completed_orders,
        sum(order_amount_usd) as lifetime_spend_usd,
        avg(order_amount_usd) as average_order_value_usd,
        min(order_date) as first_order_date,
        max(order_date) as most_recent_order_date
    from completed_orders
    group by 1
)

select * from customer_summary
