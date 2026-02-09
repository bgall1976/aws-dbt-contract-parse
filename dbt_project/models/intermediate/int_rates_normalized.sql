{{
    config(
        materialized='view',
        tags=['intermediate']
    )
}}

/*
    Normalized rate schedules with enriched attributes.
*/

with rates as (
    select * from {{ ref('stg_rate_schedules') }}
),

contracts as (
    select
        contract_id,
        contract_status
    from {{ ref('int_contracts_enriched') }}
),

-- Reference data for service categories (use seed if available)
{% set ref_exists = adapter.get_relation(
    database=target.database,
    schema=target.schema,
    identifier='ref_service_categories'
) %}

final as (
    select
        r.rate_schedule_id,
        r.contract_id,
        r.payer_id,
        r.provider_npi,
        r.rate_line_number,
        r.service_category,
        {% if ref_exists %}
        coalesce(ref.category_name, r.service_category) as service_category_name,
        {% else %}
        r.service_category as service_category_name,
        {% endif %}
        r.cpt_code,
        r.description,
        r.rate_type,
        r.rate_amount,
        
        -- Normalized rate (convert percentages to decimals if needed)
        case 
            when upper(r.rate_type) = 'PERCENTAGE' and r.rate_amount > 1 then r.rate_amount / 100
            else r.rate_amount
        end as normalized_rate,
        
        r.rate_effective_date,
        r.rate_unit,
        r.rate_modifier,
        r.contract_effective_date,
        r.contract_termination_date,
        
        -- Rate status
        case 
            when r.contract_termination_date is not null and r.contract_termination_date < current_date then 'EXPIRED'
            when r.rate_effective_date is not null and r.rate_effective_date > current_date then 'FUTURE'
            else 'ACTIVE'
        end as rate_status,
        
        c.contract_status,
        
        r._loaded_at
        
    from rates r
    left join contracts c on r.contract_id = c.contract_id
    {% if ref_exists %}
    left join {{ ref('ref_service_categories') }} ref on upper(r.service_category) = upper(ref.category_code)
    {% endif %}
)

select * from final
