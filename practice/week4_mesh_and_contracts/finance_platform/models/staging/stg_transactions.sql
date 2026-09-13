with source as (
    select * from {{ source('finance_raw', 'raw_transactions') }}
),

renamed as (
    select
        cast(transaction_id as {{ dbt.type_string() }})   as transaction_id,
        cast(customer_id as {{ dbt.type_string() }})      as customer_id,
        cast(transaction_date as date)                     as transaction_date,
        cast(amount_cents as {{ dbt.type_numeric() }}) / 100.0 as amount_usd,
        cast(currency as {{ dbt.type_string() }})          as currency,
        lower(trim(cast(payment_method as {{ dbt.type_string() }}))) as payment_method,
        lower(trim(cast(status as {{ dbt.type_string() }})))         as status,
        cast(updated_at as {{ dbt.type_timestamp() }})     as updated_at,
        -- derived flags
        case
            when lower(trim(cast(status as {{ dbt.type_string() }}))) = 'refunded'
            then true else false
        end as is_refund
    from source
)

select * from renamed
