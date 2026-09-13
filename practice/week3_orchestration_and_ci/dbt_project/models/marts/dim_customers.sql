with customers as (
    select * from {{ ref('stg_customers') }}
),

order_summary as (
    select * from {{ ref('int_customer_order_summary') }}
),

joined as (
    select
        c.customer_id,
        c.full_name,
        c.email,
        c.country_code,
        c.signup_date,
        coalesce(s.total_completed_orders, 0) as total_completed_orders,
        coalesce(s.lifetime_spend_usd, 0.0) as lifetime_spend_usd,
        coalesce(s.average_order_value_usd, 0.0) as average_order_value_usd,
        s.first_order_date,
        s.most_recent_order_date,
        case
            when coalesce(s.lifetime_spend_usd, 0.0) >= 200.0 then 'Gold'
            when coalesce(s.lifetime_spend_usd, 0.0) >= 75.0 then 'Silver'
            when coalesce(s.lifetime_spend_usd, 0.0) > 0.0 then 'Bronze'
            else 'Prospect'
        end as customer_tier
    from customers c
    left join order_summary s
        on c.customer_id = s.customer_id
)

select * from joined
