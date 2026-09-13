{{
    config(
        materialized = 'incremental',
        unique_key = 'customer_order_key',
        incremental_strategy = 'delete+insert',
        dist = 'customer_id',
        sort = 'order_date',
        on_schema_change = 'append_new_columns'
    )
}}

with orders as (
    select * from {{ ref('stg_orders_w2') }}
    {% if is_incremental() %}
        -- Lookback buffer to safely capture late-arriving records
        where order_date >= (select coalesce({{ dbt.dateadd(datepart="day", interval=-3, from_date_or_timestamp="max(order_date)") }}, '1970-01-01') from {{ this }})
    {% endif %}
),

aggregated as (
    select
        {{ dbt_utils.generate_surrogate_key(['customer_id', 'order_date']) }} as customer_order_key,
        customer_id,
        order_date,
        count(order_id) as total_orders,
        sum(gross_amount_usd) as total_revenue_usd,
        max(updated_at) as last_updated_at
    from orders
    group by 1, 2, 3
)

select * from aggregated
