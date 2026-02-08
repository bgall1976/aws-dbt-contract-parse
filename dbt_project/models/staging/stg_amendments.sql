{{
    config(
        materialized='view',
        tags=['staging', 'amendments']
    )
}}

/*
    Staging model for contract amendments.
    Uses seed data for sample amendments.
*/

with source as (
    select * from {{ ref('amendments') }}
),

contracts as (
    select * from {{ ref('stg_contracts') }}
),

joined as (
    select
        s.amendment_id,
        s.contract_id,
        c.payer_id,
        c.provider_npi,
        c.effective_date as contract_effective_date,
        cast(s.amendment_date as date) as amendment_date,
        s.description as amendment_description,
        s.rate_changes,
        row_number() over (
            partition by s.contract_id 
            order by s.amendment_date
        ) as amendment_sequence
    from source s
    left join contracts c on s.contract_id = c.contract_id
),

cleaned as (
    select
        -- Generate surrogate key
        {{ dbt_utils.generate_surrogate_key(['contract_id', 'amendment_id']) }} as amendment_key,
        
        contract_id,
        payer_id,
        provider_npi,
        
        -- Amendment details
        trim(amendment_id) as amendment_id,
        amendment_sequence,
        amendment_date as amendment_effective_date,
        trim(amendment_description) as amendment_description,
        'MODIFICATION' as amendment_type,
        trim(rate_changes) as amendment_changes,
        
        -- Contract context
        contract_effective_date,
        
        -- Audit
        current_timestamp as _loaded_at
        
    from joined
    where amendment_id is not null
)

select * from cleaned
