/*
    Custom Test: Assert Positive Rates
    
    All contracted rates must be positive values.
    Zero or negative rates indicate data quality issues.
    
    A passing test returns 0 rows.
*/

select
    rate_key,
    contract_id,
    cpt_code,
    rate_amount,
    'Non-positive rate amount' as failure_reason
from {{ ref('fact_contracted_rates') }}
where rate_amount <= 0
