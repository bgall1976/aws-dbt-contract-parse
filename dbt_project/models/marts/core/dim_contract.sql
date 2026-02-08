{{
    config(
        materialized='table',
        tags=['core', 'dimension', 'scd2']
    )
}}

/*
    Contract dimension with SCD Type 2 history tracking.
    
    This dimension captures when contract terms change over time,
    enabling point-in-time analysis of contracted rates.
    
    Uses dbt snapshots for change tracking.
*/

{# Check if snapshot exists #}
{% set snapshot_exists = adapter.get_relation(
    database=this.database,
    schema='snapshots',
    identifier='contract_snapshot'
) %}

{% if snapshot_exists %}

-- Use snapshot data when available (full SCD Type 2)
with snapshot_data as (
    select * from {{ ref('contract_snapshot') }}
),

final as (
    select
        -- Surrogate key (hash of natural key + valid_from for uniqueness)
        {{ dbt_utils.generate_surrogate_key(['contract_id', 'dbt_valid_from']) }} as contract_key,
        
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
        
        -- SCD Type 2 metadata
        dbt_valid_from as valid_from,
        dbt_valid_to as valid_to,
        case when dbt_valid_to is null then true else false end as is_current,
        
        -- Version tracking
        row_number() over (
            partition by contract_id 
            order by dbt_valid_from
        ) as version_number,
        
        -- Audit
        dbt_scd_id as scd_id,
        current_timestamp as _loaded_at
        
    from snapshot_data
)

{% else %}

-- Fallback to current data only (before snapshots are run)
with current_data as (
    select * from {{ ref('int_contracts_enriched') }}
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['contract_id']) }} as contract_key,
        contract_id,
        payer_id,
        payer_name,
        provider_npi,
        provider_name,
        effective_date,
        termination_date,
        contract_duration_days,
        contract_status,
        cast('1900-01-01' as timestamp) as valid_from,
        cast(null as timestamp) as valid_to,
        true as is_current,
        1 as version_number,
        cast(null as varchar(256)) as scd_id,
        current_timestamp as _loaded_at
    from current_data
)

{% endif %}

select * from final
