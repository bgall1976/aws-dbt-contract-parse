{{
    config(
        materialized='table',
        tags=['core', 'dimension']
    )
}}

/*
    Service/Procedure dimension table.
    Combines CPT codes and service categories from contracts
    with reference data.
*/

with rate_schedules as (
    select distinct
        service_category,
        cpt_code
    from {{ ref('stg_rate_schedules') }}
    where cpt_code is not null
),

reference as (
    select * from {{ ref('ref_service_categories') }}
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
        {{ dbt_utils.generate_surrogate_key(['rs.cpt_code']) }} as service_key,
        
        -- Natural keys
        rs.cpt_code,
        rs.service_category as category_code,
        
        -- Attributes from reference
        r.category_name,
        r.description as category_description,
        
        -- Statistics
        coalesce(ss.contracts_with_service, 0) as contracts_with_service,
        coalesce(ss.providers_offering, 0) as providers_offering,
        ss.min_rate,
        ss.max_rate,
        ss.avg_rate,
        
        -- Audit
        current_timestamp as _created_at
        
    from rate_schedules rs
    left join reference r on upper(rs.service_category) = upper(r.category_code)
    left join service_stats ss on rs.cpt_code = ss.cpt_code
)

select * from final
