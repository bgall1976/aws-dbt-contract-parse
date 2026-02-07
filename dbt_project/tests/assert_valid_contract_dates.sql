/*
    Custom Test: Assert Valid Contract Dates
    
    Contract termination date must be after effective date.
    This is a critical business rule validation.
    
    A passing test returns 0 rows.
*/

select
    contract_id,
    effective_date,
    termination_date,
    'Termination date before effective date' as failure_reason
from {{ ref('dim_contract') }}
where termination_date < effective_date
  and is_current = true
