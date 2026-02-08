{{
    config(
        materialized='view',
        tags=['staging', 'contracts']
    )
}}

/*
    Staging model for contract header data.
    Uses seed data for sample contracts.
*/

with source as (
    select * from {{ ref('contracts') }}
),

cleaned as (
    select
        -- Primary key
        contract_id,
        
        -- Payer information
        trim(payer_name) as payer_name,
        upper(trim(payer_id)) as payer_id,
        
        -- Provider information
        trim(provider_npi) as provider_npi,
        trim(provider_name) as provider_name,
        
        -- Contract dates
        cast(effective_date as date) as effective_date,
        cast(termination_date as date) as termination_date,
        
        -- Calculate contract duration
        datediff(day, 
            cast(effective_date as date), 
            cast(termination_date as date)
        ) as contract_duration_days,
        
        -- Contract status
        case 
            when cast(termination_date as date) < current_date then 'EXPIRED'
            when cast(effective_date as date) > current_date then 'FUTURE'
            else 'ACTIVE'
        end as contract_status,
        
        -- Audit columns
        current_timestamp as _loaded_at
        
    from source
    where contract_id is not null
)

select * from cleaned
