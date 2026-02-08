{{
    config(
        materialized='ephemeral',
        tags=['intermediate', 'contracts']
    )
}}

/*
    Intermediate model that enriches contract data with
    reference data and calculated fields.
*/

with contracts as (
    select * from {{ ref('stg_contracts') }}
),

payers as (
    select * from {{ ref('ref_payers') }}
),

-- Aggregate rate information per contract
rate_summary as (
    select
        contract_id,
        count(*) as total_rate_lines,
        count(distinct service_category) as unique_service_categories,
        min(rate_amount) as min_rate,
        max(rate_amount) as max_rate,
        avg(rate_amount) as avg_rate
    from {{ ref('stg_rate_schedules') }}
    group by contract_id
),

-- Count amendments per contract
amendment_summary as (
    select
        contract_id,
        count(*) as amendment_count,
        max(amendment_effective_date) as last_amendment_date
    from {{ ref('stg_amendments') }}
    group by contract_id
),

enriched as (
    select
        -- Contract core fields
        c.contract_id,
        c.payer_id,
        c.payer_name,
        c.provider_npi,
        c.provider_name,
        c.effective_date,
        c.termination_date,
        c.contract_duration_days,
        c.contract_status,
        
        -- Payer enrichment
        p.payer_type,
        p.payer_state,
        
        -- Rate summary
        coalesce(rs.total_rate_lines, 0) as total_rate_lines,
        coalesce(rs.unique_service_categories, 0) as unique_service_categories,
        rs.min_rate,
        rs.max_rate,
        rs.avg_rate,
        
        -- Amendment summary
        coalesce(amd.amendment_count, 0) as amendment_count,
        amd.last_amendment_date,
        
        -- Calculated fields
        case 
            when c.termination_date <= current_date + interval '90 days' 
                 and c.contract_status = 'ACTIVE'
            then true 
            else false 
        end as expiring_soon,
        
        datediff(day, current_date, c.termination_date) as days_until_expiration,
        
        -- Audit
        c._loaded_at
        
    from contracts c
    left join payers p on c.payer_id = p.payer_id
    left join rate_summary rs on c.contract_id = rs.contract_id
    left join amendment_summary amd on c.contract_id = amd.contract_id
)

select * from enriched
