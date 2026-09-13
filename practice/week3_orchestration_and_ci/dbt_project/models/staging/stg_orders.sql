with source as (
    select * from {{ source('raw_data', 'orders') }}
),

renamed as (
    select
        cast(id as {{ dbt.type_string() }}) as order_id,
        cast(customer_id as {{ dbt.type_string() }}) as customer_id,
        cast(order_date as date) as order_date,
        lower(trim(cast(status as {{ dbt.type_string() }}))) as order_status,
        cast(amount_cents as {{ dbt.type_numeric() }}) / 100.0 as order_amount_usd,
        lower(trim(cast(payment_method as {{ dbt.type_string() }}))) as payment_method
    from source
)

select * from renamed
