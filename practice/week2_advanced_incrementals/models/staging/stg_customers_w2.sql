with source as (
    select * from {{ source('raw_data', 'customers_w2') }}
),

renamed as (
    select
        cast(id as {{ dbt.type_string() }}) as customer_id,
        cast(name as {{ dbt.type_string() }}) as customer_name,
        cast(email as {{ dbt.type_string() }}) as email,
        cast(subscription_status as {{ dbt.type_string() }}) as subscription_status,
        cast(updated_at as {{ dbt.type_timestamp() }}) as updated_at
    from source
)

select * from renamed
