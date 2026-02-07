{% snapshot contract_snapshot %}

{{
    config(
      target_schema='snapshots',
      strategy='check',
      unique_key='contract_id',
      check_cols=[
          'payer_id',
          'payer_name', 
          'provider_npi',
          'provider_name',
          'effective_date', 
          'termination_date',
          'contract_status'
      ],
    )
}}

/*
    Contract snapshot for SCD Type 2 tracking.
    
    Captures changes to:
    - Contract dates (effective/termination)
    - Payer information
    - Provider information  
    - Contract status
    
    When any of these fields change, a new version is created
    with appropriate valid_from/valid_to timestamps.
*/

select
    contract_id,
    payer_id,
    payer_name,
    provider_npi,
    provider_name,
    effective_date,
    termination_date,
    contract_duration_days,
    contract_status,
    extracted_at,
    extraction_confidence,
    source_pdf_file,
    _loaded_at
from {{ ref('stg_contracts') }}

{% endsnapshot %}
