"""
Contract Data Schema

Pydantic models and JSON Schema validation for
extracted contract data.
"""

from datetime import date, datetime
from typing import List, Optional, Tuple, Any
from pydantic import BaseModel, Field, field_validator
import json


class RateSchedule(BaseModel):
    """Individual rate line item."""
    
    service_category: Optional[str] = None
    cpt_code: Optional[str] = None
    rate_type: str = Field(default="FEE_SCHEDULE")
    rate_amount: float = Field(gt=0)
    rate_unit: Optional[str] = "EACH"
    effective_date: Optional[str] = None
    modifier: Optional[str] = None
    
    @field_validator('rate_type')
    @classmethod
    def validate_rate_type(cls, v):
        valid_types = ['PER_DIEM', 'PERCENTAGE', 'FLAT_FEE', 'FEE_SCHEDULE', 'CASE_RATE']
        if v and v.upper() not in valid_types:
            return 'FEE_SCHEDULE'
        return v.upper() if v else 'FEE_SCHEDULE'


class Amendment(BaseModel):
    """Contract amendment or modification."""
    
    amendment_id: str
    effective_date: Optional[str] = None
    description: Optional[str] = None
    amendment_type: str = Field(default="MODIFICATION")
    changes: Optional[dict] = None
    
    @field_validator('amendment_type')
    @classmethod
    def validate_amendment_type(cls, v):
        valid_types = ['MODIFICATION', 'RATE_CHANGE', 'TERMINATION', 'EXTENSION', 'ADDENDUM']
        if v and v.upper() not in valid_types:
            return 'MODIFICATION'
        return v.upper() if v else 'MODIFICATION'


class ExtractionMetadata(BaseModel):
    """Metadata about the extraction process."""
    
    extracted_at: str
    confidence_score: float = Field(ge=0, le=1)
    source_file: str
    extractor_version: Optional[str] = "1.0.0"


class ContractData(BaseModel):
    """
    Full contract data structure.
    
    This is the schema for JSON output written to S3.
    """
    
    # Identifiers
    contract_id: str
    payer_id: Optional[str] = None
    payer_name: Optional[str] = None
    provider_npi: str = Field(min_length=10, max_length=10)
    provider_name: Optional[str] = None
    
    # Dates
    effective_date: str  # ISO format YYYY-MM-DD
    termination_date: Optional[str] = None
    
    # Nested data
    rate_schedules: List[RateSchedule] = Field(default_factory=list)
    amendments: List[Amendment] = Field(default_factory=list)
    
    # Metadata
    extraction_metadata: Optional[ExtractionMetadata] = None
    
    @field_validator('provider_npi')
    @classmethod
    def validate_npi(cls, v):
        if v and not v.isdigit():
            raise ValueError('NPI must contain only digits')
        if v and len(v) != 10:
            raise ValueError('NPI must be exactly 10 digits')
        return v
    
    @field_validator('effective_date', 'termination_date')
    @classmethod
    def validate_date_format(cls, v):
        if v is None:
            return v
        try:
            datetime.strptime(v, '%Y-%m-%d')
            return v
        except ValueError:
            raise ValueError('Date must be in YYYY-MM-DD format')
    
    class Config:
        json_schema_extra = {
            "example": {
                "contract_id": "CTR-2024-001",
                "payer_id": "BCBS-001",
                "payer_name": "Blue Cross Blue Shield",
                "provider_npi": "1234567890",
                "provider_name": "Regional Medical Center",
                "effective_date": "2024-01-01",
                "termination_date": "2026-12-31",
                "rate_schedules": [
                    {
                        "service_category": "INPATIENT",
                        "cpt_code": "99213",
                        "rate_type": "PER_DIEM",
                        "rate_amount": 1250.00,
                        "effective_date": "2024-01-01"
                    }
                ],
                "amendments": [],
                "extraction_metadata": {
                    "extracted_at": "2024-01-15T10:30:00Z",
                    "confidence_score": 0.95,
                    "source_file": "contract_bcbs_2024.pdf"
                }
            }
        }


def validate_contract(data: dict) -> Tuple[bool, List[str]]:
    """
    Validate contract data against schema.
    
    Args:
        data: Contract data dictionary
        
    Returns:
        Tuple of (is_valid, list of error messages)
    """
    errors = []
    
    try:
        ContractData(**data)
        return True, []
        
    except Exception as e:
        # Parse Pydantic validation errors
        if hasattr(e, 'errors'):
            for error in e.errors():
                field = '.'.join(str(x) for x in error['loc'])
                message = error['msg']
                errors.append(f"{field}: {message}")
        else:
            errors.append(str(e))
        
        return False, errors


def get_json_schema() -> dict:
    """Get JSON Schema for contract data."""
    return ContractData.model_json_schema()


def export_schema_to_file(filepath: str):
    """Export JSON Schema to file."""
    schema = get_json_schema()
    with open(filepath, 'w') as f:
        json.dump(schema, f, indent=2)
