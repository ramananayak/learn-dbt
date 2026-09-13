with source as (
    select * from {{ source('raw_data', 'customers') }}
),

renamed as (
    select
        cast(id as {{ dbt.type_string() }}) as customer_id,
        cast(first_name as {{ dbt.type_string() }}) as first_name,
        cast(last_name as {{ dbt.type_string() }}) as last_name,
        trim(first_name) || ' ' || trim(last_name) as full_name,
        cast(email as {{ dbt.type_string() }}) as email,
        cast(signup_date as date) as signup_date,
        upper(trim(cast(country as {{ dbt.type_string() }}))) as country_code
    from source
)

select * from renamed
