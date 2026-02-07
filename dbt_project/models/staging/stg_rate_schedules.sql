{{
    config(
        materialized='view',
        tags=['staging', 'rates']
    )
}}

/*
    Staging model for rate schedules extracted from contracts.
    Flattens the nested rate_schedules array from contract JSON.
*/

with contracts as (
    select * from {{ ref('stg_contracts') }}
),

-- Flatten the rate_schedules JSON array
flattened_rates as (
    select
        c.contract_id,
        c.payer_id,
        c.provider_npi,
        c.effective_date as contract_effective_date,
        c.termination_date as contract_termination_date,
        
        -- Extract fields from rate schedule array element
        json_extract_path_text(rs, 'service_category') as service_category,
        json_extract_path_text(rs, 'cpt_code') as cpt_code,
        json_extract_path_text(rs, 'rate_type') as rate_type,
        cast(json_extract_path_text(rs, 'rate_amount') as decimal(12,2)) as rate_amount,
        cast(json_extract_path_text(rs, 'effective_date') as date) as rate_effective_date,
        json_extract_path_text(rs, 'rate_unit') as rate_unit,
        json_extract_path_text(rs, 'modifier') as rate_modifier,
        
        -- Generate unique rate line ID
        row_number() over (
            partition by c.contract_id 
            order by json_extract_path_text(rs, 'service_category'),
                     json_extract_path_text(rs, 'cpt_code')
        ) as rate_line_number
        
    from contracts c,
    -- Redshift JSON array flattening
    json_array_elements(c.rate_schedules) as rs
    where c.rate_schedules is not null
),

cleaned as (
    select
        -- Generate surrogate key for rate line
        {{ dbt_utils.generate_surrogate_key(['contract_id', 'rate_line_number']) }} as rate_schedule_id,
        
        contract_id,
        payer_id,
        provider_npi,
        rate_line_number,
        
        -- Service information
        upper(trim(service_category)) as service_category,
        trim(cpt_code) as cpt_code,
        
        -- Rate details
        upper(trim(rate_type)) as rate_type,
        rate_amount,
        coalesce(rate_effective_date, contract_effective_date) as rate_effective_date,
        upper(trim(coalesce(rate_unit, 'EACH'))) as rate_unit,
        trim(rate_modifier) as rate_modifier,
        
        -- Contract context
        contract_effective_date,
        contract_termination_date,
        
        -- Audit
        current_timestamp as _loaded_at
        
    from flattened_rates
    where rate_amount is not null
      and rate_amount > 0
)

select * from cleaned
