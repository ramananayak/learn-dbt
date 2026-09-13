with source as (
    select * from {{ source('raw_data', 'orders_w2') }}
),

renamed as (
    select
        cast(id as {{ dbt.type_string() }}) as order_id,
        cast(customer_id as {{ dbt.type_string() }}) as customer_id,
        cast(order_date as date) as order_date,
        cast(status as {{ dbt.type_string() }}) as order_status,
        cast(amount as {{ dbt.type_numeric() }}) as gross_amount_usd,
        cast(updated_at as {{ dbt.type_timestamp() }}) as updated_at
    from source
)

select * from renamed
