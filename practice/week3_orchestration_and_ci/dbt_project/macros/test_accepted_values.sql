{% test accepted_values(model, column_name, values=none, quote=True, arguments=none) %}

{%- if arguments is not none -%}
  {%- set values = arguments.get('values', values) -%}
  {%- set quote = arguments.get('quote', quote) -%}
{%- endif -%}

with all_values as (
    select distinct
        {{ column_name }} as value_field
    from {{ model }}
),

validation_errors as (
    select
        value_field
    from all_values
    where value_field not in (
        {% for value in values -%}
            {% if quote -%}
                '{{ value }}'
            {%- else -%}
                {{ value }}
            {%- endif -%}
            {%- if not loop.last -%},{%- endif %}
        {% endfor %}
    )
)

select *
from validation_errors

{% endtest %}
