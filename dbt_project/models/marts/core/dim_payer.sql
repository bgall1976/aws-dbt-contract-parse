{{
    config(
        materialized='table',
        tags=['core', 'dimension']
    )
}}

/*
    Payer dimension table.
    Combines extracted payer data with reference data.
*/

with contracts as (
    select distinct
        payer_id,
        payer_name
    from {{ ref('stg_contracts') }}
    where payer_id is not null
),

reference as (
    select * from {{ ref('ref_payers') }}
),

-- Aggregate stats per payer
payer_stats as (
    select
        payer_id,
        count(distinct contract_id) as total_contracts,
        count(distinct provider_npi) as contracted_providers,
        min(effective_date) as first_contract_date,
        max(termination_date) as latest_contract_end
    from {{ ref('stg_contracts') }}
    group by payer_id
),

final as (
    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['coalesce(r.payer_id, c.payer_id)']) }} as payer_key,
        
        -- Natural key
        coalesce(r.payer_id, c.payer_id) as payer_id,
        
        -- Attributes from reference or extracted
        coalesce(r.payer_name, c.payer_name) as payer_name,
        r.payer_type,
        r.payer_state,
        r.payer_website,
        
        -- Derived metrics
        coalesce(ps.total_contracts, 0) as total_contracts,
        coalesce(ps.contracted_providers, 0) as contracted_providers,
        ps.first_contract_date,
        ps.latest_contract_end,
        
        -- Status
        case 
            when ps.latest_contract_end >= current_date then 'ACTIVE'
            when ps.payer_id is null then 'REFERENCE_ONLY'
            else 'INACTIVE'
        end as payer_status,
        
        -- Audit
        current_timestamp as _created_at
        
    from reference r
    full outer join contracts c on r.payer_id = c.payer_id
    left join payer_stats ps on coalesce(r.payer_id, c.payer_id) = ps.payer_id
)

select * from final
