{{
    config(
        materialized='view',
        tags=['intermediate']
    )
}}

/*
    Enriched contracts with calculated fields and aggregations.
*/

with contracts as (
    select * from {{ ref('stg_contracts') }}
),

rate_stats as (
    select
        contract_id,
        count(*) as rate_schedule_count,
        sum(rate_amount) as total_rate_value,
        avg(rate_amount) as avg_rate_amount,
        min(rate_amount) as min_rate_amount,
        max(rate_amount) as max_rate_amount
    from {{ ref('stg_rate_schedules') }}
    group by contract_id
),

amendment_stats as (
    select
        contract_id,
        count(*) as amendment_count,
        max(amendment_effective_date) as last_amendment_date
    from {{ ref('stg_amendments') }}
    group by contract_id
),

final as (
    select
        c.contract_id,
        c.payer_id,
        c.payer_name,
        c.provider_npi,
        c.provider_name,
        c.effective_date,
        c.termination_date,
        
        -- Calculated duration
        datediff(day, c.effective_date, coalesce(c.termination_date, current_date)) as contract_duration_days,
        
        -- Contract status
        case 
            when c.termination_date is not null and c.termination_date < current_date then 'EXPIRED'
            when c.effective_date is not null and c.effective_date > current_date then 'FUTURE'
            when c.effective_date is null then 'UNKNOWN'
            else 'ACTIVE'
        end as contract_status,
        
        -- Rate statistics
        coalesce(rs.rate_schedule_count, 0) as rate_schedule_count,
        rs.total_rate_value,
        rs.avg_rate_amount,
        rs.min_rate_amount,
        rs.max_rate_amount,
        
        -- Amendment statistics
        coalesce(ams.amendment_count, 0) as amendment_count,
        ams.last_amendment_date,
        
        -- Extraction quality
        c.confidence_score,
        c.source_file,
        c.extracted_at,
        
        -- Audit
        c.loaded_at,
        current_timestamp as _enriched_at
        
    from contracts c
    left join rate_stats rs on c.contract_id = rs.contract_id
    left join amendment_stats ams on c.contract_id = ams.contract_id
)

select * from final
