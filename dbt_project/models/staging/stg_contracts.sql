{{
    config(
        materialized='view',
        tags=['staging', 'contracts']
    )
}}

/*
    Staging model for contract header data.
    Uses raw_contracts table loaded from S3.
*/

with source as (
    select * from {{ source('raw_contracts', 'raw_contracts') }}
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
        trim(replace(provider_name, chr(9), ' ')) as provider_name,
        
        -- Contract dates (stored as varchar, convert to date)
        case 
            when effective_date is not null and effective_date != '' and effective_date != 'null'
            then cast(effective_date as date)
            else null
        end as effective_date,
        
        case 
            when termination_date is not null and termination_date != '' and termination_date != 'null'
            then cast(termination_date as date)
            else null
        end as termination_date,
        
        -- Nested data (SUPER type)
        rate_schedules,
        amendments,
        
        -- Extraction metadata (use SUPER dot notation)
        extraction_metadata.extracted_at::varchar as extracted_at,
        extraction_metadata.confidence_score::decimal(5,4) as confidence_score,
        extraction_metadata.source_file::varchar as source_file,
        
        -- Audit columns
        loaded_at,
        current_timestamp as _dbt_loaded_at
        
    from source
    where contract_id is not null
)

select * from cleaned
