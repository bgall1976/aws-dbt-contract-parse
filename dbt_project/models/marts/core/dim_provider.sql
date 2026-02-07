{{
    config(
        materialized='table',
        tags=['core', 'dimension']
    )
}}

/*
    Provider dimension table.
    Deduplicates providers across multiple contracts.
*/

with contracts as (
    select distinct
        provider_npi,
        provider_name
    from {{ ref('stg_contracts') }}
    where provider_npi is not null
),

-- Get the most recent provider name if there are duplicates
deduplicated as (
    select
        provider_npi,
        provider_name,
        row_number() over (
            partition by provider_npi 
            order by provider_name
        ) as rn
    from contracts
),

-- Aggregate contract stats per provider
provider_stats as (
    select
        provider_npi,
        count(distinct contract_id) as total_contracts,
        count(distinct payer_id) as unique_payers,
        min(effective_date) as first_contract_date,
        max(termination_date) as latest_contract_end
    from {{ ref('stg_contracts') }}
    group by provider_npi
),

final as (
    select
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['d.provider_npi']) }} as provider_key,
        
        -- Natural key
        d.provider_npi,
        
        -- Attributes
        d.provider_name,
        
        -- Derived metrics
        coalesce(ps.total_contracts, 0) as total_contracts,
        coalesce(ps.unique_payers, 0) as unique_payers,
        ps.first_contract_date,
        ps.latest_contract_end,
        
        -- Status
        case 
            when ps.latest_contract_end >= current_date then 'ACTIVE'
            else 'INACTIVE'
        end as provider_status,
        
        -- Audit
        current_timestamp as _created_at
        
    from deduplicated d
    left join provider_stats ps on d.provider_npi = ps.provider_npi
    where d.rn = 1
)

select * from final
