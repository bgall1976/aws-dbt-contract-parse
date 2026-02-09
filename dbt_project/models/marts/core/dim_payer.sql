{{
    config(
        materialized='table',
        tags=['core', 'dimension']
    )
}}

/*
    Payer dimension table.
    Built from extracted contract data.
*/

with contracts as (
    select distinct
        payer_id,
        payer_name
    from {{ ref('stg_contracts') }}
    where payer_id is not null
),

-- Check if reference seed exists
{% set ref_exists = adapter.get_relation(
    database=target.database,
    schema=target.schema,
    identifier='ref_payers'
) %}

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
        md5(c.payer_id) as payer_key,
        
        -- Natural key
        c.payer_id,
        
        -- Attributes
        c.payer_name,
        {% if ref_exists %}
        r.payer_type,
        r.payer_state,
        r.payer_website,
        {% else %}
        null::varchar(50) as payer_type,
        null::varchar(2) as payer_state,
        null::varchar(255) as payer_website,
        {% endif %}
        
        -- Derived metrics
        coalesce(ps.total_contracts, 0) as total_contracts,
        coalesce(ps.contracted_providers, 0) as contracted_providers,
        ps.first_contract_date,
        ps.latest_contract_end,
        
        -- Status
        case 
            when ps.latest_contract_end >= current_date or ps.latest_contract_end is null then 'ACTIVE'
            else 'INACTIVE'
        end as payer_status,
        
        -- Audit
        current_timestamp as _created_at
        
    from contracts c
    left join payer_stats ps on c.payer_id = ps.payer_id
    {% if ref_exists %}
    left join {{ ref('ref_payers') }} r on c.payer_id = r.payer_id
    {% endif %}
)

select * from final
