with source as (
    select * from {{ source('marketing_raw', 'raw_customer_segments') }}
)

select
    cast(customer_id as {{ dbt.type_string() }})         as customer_id,
    cast(segment as {{ dbt.type_string() }})              as segment,
    cast(acquisition_channel as {{ dbt.type_string() }}) as acquisition_channel,
    cast(cohort_month as date)                            as cohort_month
from source
