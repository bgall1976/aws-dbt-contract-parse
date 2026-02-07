{{
    config(
        materialized='ephemeral',
        tags=['intermediate', 'rates']
    )
}}

/*
    Intermediate model that normalizes rate schedules into a
    standard structure for analysis and comparison.
*/

with rate_schedules as (
    select * from {{ ref('stg_rate_schedules') }}
),

service_categories as (
    select * from {{ ref('ref_service_categories') }}
),

contracts as (
    select 
        contract_id,
        payer_name,
        provider_name,
        contract_status
    from {{ ref('stg_contracts') }}
),

normalized as (
    select
        -- Keys
        rs.rate_schedule_id,
        rs.contract_id,
        rs.payer_id,
        rs.provider_npi,
        
        -- Contract context
        c.payer_name,
        c.provider_name,
        c.contract_status,
        
        -- Rate details
        rs.rate_line_number,
        rs.service_category,
        sc.category_name as service_category_name,
        sc.description as service_category_description,
        rs.cpt_code,
        rs.rate_type,
        rs.rate_amount,
        rs.rate_unit,
        rs.rate_modifier,
        
        -- Dates
        rs.rate_effective_date,
        rs.contract_effective_date,
        rs.contract_termination_date,
        
        -- Normalized rate for comparison (convert all to per-unit)
        case rs.rate_type
            when 'PER_DIEM' then rs.rate_amount
            when 'PERCENTAGE' then rs.rate_amount  -- Keep as percentage
            when 'FLAT_FEE' then rs.rate_amount
            when 'CASE_RATE' then rs.rate_amount
            else rs.rate_amount
        end as normalized_rate,
        
        -- Rate status
        case 
            when rs.rate_effective_date > current_date then 'FUTURE'
            when rs.contract_termination_date < current_date then 'EXPIRED'
            else 'ACTIVE'
        end as rate_status,
        
        -- Audit
        rs._loaded_at
        
    from rate_schedules rs
    left join service_categories sc 
        on upper(rs.service_category) = upper(sc.category_code)
    left join contracts c 
        on rs.contract_id = c.contract_id
)

select * from normalized
