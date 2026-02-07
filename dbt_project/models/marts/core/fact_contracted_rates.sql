{{
    config(
        materialized='table',
        tags=['core', 'fact'],
        sort=['contract_key', 'service_key'],
        dist='contract_key'
    )
}}

/*
    Fact table for contracted rates.
    
    Grain: One row per rate line per contract.
    
    This table contains the negotiated rates between
    providers and payers for specific services.
*/

with rates as (
    select * from {{ ref('int_rates_normalized') }}
),

contracts as (
    select 
        contract_key,
        contract_id,
        is_current as contract_is_current
    from {{ ref('dim_contract') }}
    where is_current = true  -- Join to current contract version
),

providers as (
    select provider_key, provider_npi
    from {{ ref('dim_provider') }}
),

payers as (
    select payer_key, payer_id
    from {{ ref('dim_payer') }}
),

services as (
    select service_key, cpt_code
    from {{ ref('dim_service') }}
),

dates as (
    select date_key, full_date
    from {{ ref('dim_date') }}
),

final as (
    select
        -- Surrogate key for fact
        {{ dbt_utils.generate_surrogate_key([
            'r.rate_schedule_id',
            'c.contract_key'
        ]) }} as rate_key,
        
        -- Dimension keys
        c.contract_key,
        p.provider_key,
        py.payer_key,
        s.service_key,
        d_eff.date_key as effective_date_key,
        d_term.date_key as termination_date_key,
        
        -- Degenerate dimensions
        r.rate_schedule_id,
        r.contract_id,
        r.rate_line_number,
        r.cpt_code,
        
        -- Measures
        r.rate_amount,
        r.normalized_rate,
        
        -- Rate attributes
        r.rate_type,
        r.rate_unit,
        r.rate_modifier,
        r.service_category,
        r.service_category_name,
        
        -- Status
        r.rate_status,
        r.contract_status,
        
        -- Dates (for filtering without joins)
        r.rate_effective_date,
        r.contract_effective_date,
        r.contract_termination_date,
        
        -- Audit
        r._loaded_at,
        current_timestamp as _created_at
        
    from rates r
    inner join contracts c on r.contract_id = c.contract_id
    inner join providers p on r.provider_npi = p.provider_npi
    inner join payers py on r.payer_id = py.payer_id
    left join services s on r.cpt_code = s.cpt_code
    left join dates d_eff on r.rate_effective_date = d_eff.full_date
    left join dates d_term on r.contract_termination_date = d_term.full_date
)

select * from final
