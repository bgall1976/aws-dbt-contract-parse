{{
    config(
        materialized='view',
        tags=['staging', 'amendments']
    )
}}

/*
    Staging model for contract amendments.
    Unnests amendments SUPER array from raw_contracts.
*/

with contracts as (
    select 
        contract_id,
        payer_id,
        provider_npi,
        effective_date as contract_effective_date,
        amendments
    from {{ ref('stg_contracts') }}
    where amendments is not null
),

-- Unnest the SUPER array
unnested as (
    select
        c.contract_id,
        c.payer_id,
        c.provider_npi,
        c.contract_effective_date,
        a.amendment_id::varchar(100) as amendment_id,
        a.amendment_date::varchar(50) as amendment_date_raw,
        a.description::varchar(1000) as amendment_description,
        a.rate_changes::varchar(2000) as rate_changes
    from contracts c, c.amendments as a
),

cleaned as (
    select
        -- Generate surrogate key
        md5(contract_id || '-' || coalesce(amendment_id, '') || '-' || row_number() over (partition by contract_id order by amendment_date_raw)::varchar) as amendment_key,
        
        contract_id,
        payer_id,
        provider_npi,
        
        -- Amendment details
        coalesce(trim(amendment_id), 'AMD-' || contract_id || '-' || row_number() over (partition by contract_id order by amendment_date_raw)::varchar) as amendment_id,
        row_number() over (partition by contract_id order by amendment_date_raw) as amendment_sequence,
        case 
            when amendment_date_raw is not null and amendment_date_raw != '' and amendment_date_raw != 'null'
            then cast(amendment_date_raw as date)
            else null
        end as amendment_effective_date,
        trim(amendment_description) as amendment_description,
        'MODIFICATION' as amendment_type,
        trim(rate_changes) as amendment_changes,
        
        -- Contract context
        contract_effective_date,
        
        -- Audit
        current_timestamp as _loaded_at
        
    from unnested
)

select * from cleaned
