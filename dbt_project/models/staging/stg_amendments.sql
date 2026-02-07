{{
    config(
        materialized='view',
        tags=['staging', 'amendments']
    )
}}

/*
    Staging model for contract amendments extracted from PDFs.
    Flattens the nested amendments array from contract JSON.
*/

with contracts as (
    select * from {{ ref('stg_contracts') }}
),

-- Flatten the amendments JSON array
flattened_amendments as (
    select
        c.contract_id,
        c.payer_id,
        c.provider_npi,
        c.effective_date as contract_effective_date,
        
        -- Extract fields from amendment array element
        json_extract_path_text(amd, 'amendment_id') as amendment_id,
        cast(json_extract_path_text(amd, 'effective_date') as date) as amendment_effective_date,
        json_extract_path_text(amd, 'description') as amendment_description,
        json_extract_path_text(amd, 'amendment_type') as amendment_type,
        json_extract_path_text(amd, 'changes') as amendment_changes_json,
        
        -- Sequence amendments
        row_number() over (
            partition by c.contract_id 
            order by cast(json_extract_path_text(amd, 'effective_date') as date)
        ) as amendment_sequence
        
    from contracts c,
    json_array_elements(c.amendments) as amd
    where c.amendments is not null
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
        amendment_effective_date,
        trim(amendment_description) as amendment_description,
        upper(trim(coalesce(amendment_type, 'MODIFICATION'))) as amendment_type,
        amendment_changes_json,
        
        -- Contract context
        contract_effective_date,
        
        -- Audit
        current_timestamp as _loaded_at
        
    from flattened_amendments
    where amendment_id is not null
)

select * from cleaned
