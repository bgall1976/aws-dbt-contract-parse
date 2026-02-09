{{
    config(
        materialized='table',
        tags=['core', 'dimension']
    )
}}

/*
    Contract dimension table.
    Contains enriched contract data.
*/

with enriched as (
    select * from {{ ref('int_contracts_enriched') }}
),

final as (
    select
        -- Surrogate key
        md5(contract_id) as contract_key,
        
        -- Natural key
        contract_id,
        
        -- Payer information
        payer_id,
        payer_name,
        
        -- Provider information
        provider_npi,
        provider_name,
        
        -- Contract dates
        effective_date,
        termination_date,
        contract_duration_days,
        contract_status,
        
        -- Statistics
        rate_schedule_count,
        amendment_count,
        last_amendment_date,
        avg_rate_amount,
        
        -- Extraction quality
        confidence_score,
        source_file,
        extracted_at,
        
        -- SCD fields (simplified - no snapshot)
        cast('1900-01-01' as timestamp) as valid_from,
        cast(null as timestamp) as valid_to,
        true as is_current,
        1 as version_number,
        
        -- Audit
        current_timestamp as _created_at
        
    from enriched
)

select * from final
