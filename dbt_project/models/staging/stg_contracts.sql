{{
    config(
        materialized='view',
        tags=['staging', 'contracts']
    )
}}

/*
    Staging model for contract header data extracted from PDFs.
    Cleans and type-casts the raw JSON data from S3.
*/

with source as (
    select * from {{ source('s3_json', 'contracts') }}
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
        
        -- Nested data (keep as JSON for downstream processing)
        rate_schedules,
        amendments,
        
        -- Extraction metadata
        cast(extraction_metadata.extracted_at as timestamp) as extracted_at,
        extraction_metadata.confidence_score as extraction_confidence,
        extraction_metadata.source_file as source_pdf_file,
        
        -- Audit columns
        current_timestamp as _loaded_at
        
    from source
    where contract_id is not null
      and provider_npi is not null
)

select * from cleaned
