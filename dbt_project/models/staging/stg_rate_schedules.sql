{{
    config(
        materialized='view',
        tags=['staging', 'rates']
    )
}}

/*
    Staging model for rate schedules.
    Uses seed data for sample rate schedules.
*/

with source as (
    select * from {{ ref('rate_schedules') }}
),

contracts as (
    select * from {{ ref('stg_contracts') }}
),

joined as (
    select
        s.contract_id,
        c.payer_id,
        c.provider_npi,
        c.effective_date as contract_effective_date,
        c.termination_date as contract_termination_date,
        s.service_category,
        s.cpt_code,
        s.rate_type,
        cast(s.rate_amount as decimal(12,2)) as rate_amount,
        cast(s.effective_date as date) as rate_effective_date,
        s.rate_unit,
        s.modifier as rate_modifier,
        row_number() over (
            partition by s.contract_id 
            order by s.service_category, s.cpt_code
        ) as rate_line_number
    from source s
    left join contracts c on s.contract_id = c.contract_id
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
        
    from joined
    where rate_amount is not null
      and rate_amount > 0
)

select * from cleaned
