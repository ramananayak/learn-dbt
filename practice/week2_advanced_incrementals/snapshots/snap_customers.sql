{% snapshot snap_customers %}

{{
    config(
      target_schema='snapshots',
      unique_key='customer_id',
      strategy='timestamp',
      updated_at='updated_at',
      invalidate_hard_deletes=True
    )
}}

select
    customer_id,
    customer_name,
    email,
    subscription_status,
    updated_at
from {{ ref('stg_customers_w2') }}

{% endsnapshot %}
