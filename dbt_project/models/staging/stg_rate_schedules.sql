{{
    config(
        materialized='view',
        tags=['staging', 'rates']
    )
}}

/*
    Staging model for rate schedules.
    Unnests rate_schedules SUPER array from raw_contracts.
*/

with contracts as (
    select 
        contract_id,
        payer_id,
        provider_npi,
        effective_date as contract_effective_date,
        termination_date as contract_termination_date,
        rate_schedules
    from {{ ref('stg_contracts') }}
    where rate_schedules is not null
),

-- Unnest the SUPER array
unnested as (
    select
        c.contract_id,
        c.payer_id,
        c.provider_npi,
        c.contract_effective_date,
        c.contract_termination_date,
        rs.service_category::varchar(100) as service_category,
        rs.cpt_code::varchar(20) as cpt_code,
        rs.description::varchar(500) as description,
        rs.rate_type::varchar(50) as rate_type,
        rs.rate_amount::decimal(12,2) as rate_amount,
        rs.effective_date::varchar(50) as rate_effective_date_raw,
        rs.rate_unit::varchar(20) as rate_unit,
        rs.modifier::varchar(20) as rate_modifier
    from contracts c, c.rate_schedules as rs
),

cleaned as (
    select
        -- Generate surrogate key for rate line
        md5(contract_id || '-' || coalesce(cpt_code, '') || '-' || coalesce(service_category, '') || '-' || row_number() over (partition by contract_id order by service_category, cpt_code)::varchar) as rate_schedule_id,
        
        contract_id,
        payer_id,
        provider_npi,
        row_number() over (partition by contract_id order by service_category, cpt_code) as rate_line_number,
        
        -- Service information
        upper(trim(service_category)) as service_category,
        trim(cpt_code) as cpt_code,
        trim(description) as description,
        
        -- Rate details
        upper(trim(rate_type)) as rate_type,
        rate_amount,
        case 
            when rate_effective_date_raw is not null and rate_effective_date_raw != '' and rate_effective_date_raw != 'null'
            then cast(rate_effective_date_raw as date)
            else contract_effective_date
        end as rate_effective_date,
        upper(trim(coalesce(rate_unit, 'EACH'))) as rate_unit,
        trim(rate_modifier) as rate_modifier,
        
        -- Contract context
        contract_effective_date,
        contract_termination_date,
        
        -- Audit
        current_timestamp as _loaded_at
        
    from unnested
    where rate_amount is not null
      and rate_amount > 0
)

select * from cleaned
