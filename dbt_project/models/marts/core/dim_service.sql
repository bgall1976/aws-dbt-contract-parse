{{
    config(
        materialized='table',
        tags=['core', 'dimension']
    )
}}

/*
    Service/Procedure dimension table.
    Built from rate schedules extracted from contracts.
*/

-- Check if reference seed exists
{% set ref_exists = adapter.get_relation(
    database=target.database,
    schema=target.schema,
    identifier='ref_service_categories'
) %}

with rate_schedules as (
    select distinct
        service_category,
        cpt_code
    from {{ ref('stg_rate_schedules') }}
    where cpt_code is not null
),

-- Get rate statistics per service
service_stats as (
    select
        cpt_code,
        count(distinct contract_id) as contracts_with_service,
        count(distinct provider_npi) as providers_offering,
        min(rate_amount) as min_rate,
        max(rate_amount) as max_rate,
        avg(rate_amount) as avg_rate
    from {{ ref('stg_rate_schedules') }}
    group by cpt_code
),

final as (
    select
        -- Surrogate key
        md5(rs.cpt_code) as service_key,
        
        -- Natural keys
        rs.cpt_code,
        rs.service_category as category_code,
        
        -- Attributes from reference (if available)
        {% if ref_exists %}
        r.category_name,
        r.description as category_description,
        {% else %}
        rs.service_category as category_name,
        null::varchar(500) as category_description,
        {% endif %}
        
        -- Statistics
        coalesce(ss.contracts_with_service, 0) as contracts_with_service,
        coalesce(ss.providers_offering, 0) as providers_offering,
        ss.min_rate,
        ss.max_rate,
        ss.avg_rate,
        
        -- Audit
        current_timestamp as _created_at
        
    from rate_schedules rs
    left join service_stats ss on rs.cpt_code = ss.cpt_code
    {% if ref_exists %}
    left join {{ ref('ref_service_categories') }} ref on upper(rs.service_category) = upper(ref.category_code)
    {% endif %}
)

select * from final
