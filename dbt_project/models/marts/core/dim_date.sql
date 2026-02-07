{{
    config(
        materialized='table',
        tags=['core', 'dimension']
    )
}}

/*
    Standard date dimension table.
    Generates dates from 2020 to 2030 for contract analysis.
*/

with date_spine as (
    {{ dbt_date.get_date_dimension('2020-01-01', '2030-12-31') }}
),

final as (
    select
        -- Integer key (YYYYMMDD format)
        cast(to_char(date_day, 'YYYYMMDD') as integer) as date_key,
        
        -- Full date
        date_day as full_date,
        
        -- Year attributes
        date_part(year, date_day) as year,
        date_part(quarter, date_day) as quarter,
        date_part(month, date_day) as month,
        to_char(date_day, 'Month') as month_name,
        to_char(date_day, 'Mon') as month_abbr,
        
        -- Week attributes
        date_part(week, date_day) as week_of_year,
        date_part(dayofweek, date_day) as day_of_week,
        to_char(date_day, 'Day') as day_name,
        to_char(date_day, 'Dy') as day_abbr,
        
        -- Day attributes
        date_part(day, date_day) as day_of_month,
        date_part(dayofyear, date_day) as day_of_year,
        
        -- Fiscal year (assuming Jan start)
        date_part(year, date_day) as fiscal_year,
        date_part(quarter, date_day) as fiscal_quarter,
        
        -- Flags
        case when date_part(dayofweek, date_day) in (0, 6) then true else false end as is_weekend,
        false as is_holiday,  -- Would need holiday calendar
        
        -- Period descriptors
        to_char(date_day, 'YYYY-MM') as year_month,
        to_char(date_day, 'YYYY') || '-Q' || date_part(quarter, date_day) as year_quarter,
        
        -- Relative flags
        case when date_day = current_date then true else false end as is_today,
        case when date_day = current_date - 1 then true else false end as is_yesterday,
        case when date_trunc('month', date_day) = date_trunc('month', current_date) 
             then true else false end as is_current_month,
        case when date_trunc('year', date_day) = date_trunc('year', current_date) 
             then true else false end as is_current_year
        
    from date_spine
)

select * from final
