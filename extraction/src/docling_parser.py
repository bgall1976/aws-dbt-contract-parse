"""
Docling PDF Parser

Uses Docling for AI-powered document understanding
to extract structured contract data from PDFs.
"""

import re
from datetime import datetime
from typing import Optional, Dict, Any, List
from pathlib import Path

import structlog

# Docling imports (with fallback for environments without it)
try:
    from docling.document_converter import DocumentConverter
    from docling.datamodel.base_models import InputFormat
    DOCLING_AVAILABLE = True
except ImportError:
    DOCLING_AVAILABLE = False

logger = structlog.get_logger(__name__)


class DoclingParser:
    """
    Parser that uses Docling for intelligent PDF extraction.
    
    Docling provides:
    - Layout analysis
    - Table extraction
    - Text classification
    - Entity recognition
    """
    
    def __init__(self):
        if DOCLING_AVAILABLE:
            self.converter = DocumentConverter()
            logger.info("Docling parser initialized")
        else:
            self.converter = None
            logger.warning("Docling not available, using fallback parser")
    
    def parse_contract(self, pdf_path: str) -> Optional[Dict[str, Any]]:
        """
        Parse a contract PDF and extract structured data.
        
        Args:
            pdf_path: Path to the PDF file
            
        Returns:
            Extracted contract data as dictionary
        """
        logger.info("Parsing contract PDF", path=pdf_path)
        
        try:
            if DOCLING_AVAILABLE:
                return self._parse_with_docling(pdf_path)
            else:
                return self._parse_fallback(pdf_path)
                
        except Exception as e:
            logger.exception("Error parsing PDF", path=pdf_path, error=str(e))
            return None
    
    def _parse_with_docling(self, pdf_path: str) -> Dict[str, Any]:
        """Parse using Docling document converter."""
        
        # Convert PDF to structured document
        result = self.converter.convert(pdf_path)
        doc = result.document
        
        # Extract text content
        full_text = doc.export_to_markdown()
        
        # Extract tables
        tables = self._extract_tables(doc)
        
        # Parse contract fields from text
        contract_data = self._extract_contract_fields(full_text)
        
        # Extract rate schedules from tables
        contract_data["rate_schedules"] = self._extract_rate_schedules(tables)
        
        # Extract amendments
        contract_data["amendments"] = self._extract_amendments(full_text)
        
        # Calculate confidence score
        contract_data["_confidence"] = self._calculate_confidence(contract_data)
        
        return contract_data
    
    def _parse_fallback(self, pdf_path: str) -> Dict[str, Any]:
        """Fallback parser using pypdf when Docling is unavailable."""
        
        try:
            from pypdf import PdfReader
        except ImportError:
            logger.error("Neither Docling nor pypdf available")
            return None
        
        reader = PdfReader(pdf_path)
        full_text = ""
        
        for page in reader.pages:
            full_text += page.extract_text() + "\n"
        
        # Parse contract fields from text
        contract_data = self._extract_contract_fields(full_text)
        
        # Basic rate schedule extraction (limited without table detection)
        contract_data["rate_schedules"] = []
        contract_data["amendments"] = []
        
        # Lower confidence for fallback parser
        contract_data["_confidence"] = self._calculate_confidence(contract_data) * 0.7
        
        return contract_data
    
    def _extract_tables(self, doc) -> List[Dict[str, Any]]:
        """Extract tables from Docling document."""
        tables = []
        
        for item in doc.iterate_items():
            if hasattr(item, 'table') and item.table is not None:
                table_data = {
                    "headers": [],
                    "rows": []
                }
                
                # Extract table structure
                table = item.table
                if hasattr(table, 'data'):
                    for i, row in enumerate(table.data):
                        if i == 0:
                            table_data["headers"] = [str(cell) for cell in row]
                        else:
                            table_data["rows"].append([str(cell) for cell in row])
                
                tables.append(table_data)
        
        return tables
    
    def _extract_contract_fields(self, text: str) -> Dict[str, Any]:
        """Extract key contract fields using regex patterns."""
        
        contract_data = {
            "contract_id": None,
            "payer_name": None,
            "payer_id": None,
            "provider_npi": None,
            "provider_name": None,
            "effective_date": None,
            "termination_date": None,
        }
        
        # Contract ID patterns
        contract_id_patterns = [
            r"Contract\s*(?:Number|No|#|ID)[:\s]*([A-Z0-9\-]+)",
            r"Agreement\s*(?:Number|No|#)[:\s]*([A-Z0-9\-]+)",
            r"CTR[:\s\-]*(\d+)",
        ]
        
        for pattern in contract_id_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                contract_data["contract_id"] = match.group(1).strip()
                break
        
        # Generate contract ID if not found
        if not contract_data["contract_id"]:
            contract_data["contract_id"] = f"CTR-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        
        # NPI pattern (exactly 10 digits)
        npi_match = re.search(r"NPI[:\s#]*(\d{10})", text, re.IGNORECASE)
        if npi_match:
            contract_data["provider_npi"] = npi_match.group(1)
        
        # Provider name patterns
        provider_patterns = [
            r"Provider[:\s]+([A-Za-z\s\.,]+(?:Hospital|Medical|Health|Center|Clinic))",
            r"Facility[:\s]+([A-Za-z\s\.,]+(?:Hospital|Medical|Health|Center|Clinic))",
        ]
        
        for pattern in provider_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                contract_data["provider_name"] = match.group(1).strip()
                break
        
        # Payer name patterns
        payer_patterns = [
            r"(?:Payer|Insurance|Plan)[:\s]+([A-Za-z\s]+(?:Blue Cross|Aetna|UnitedHealth|Cigna|Humana|Anthem))",
            r"(Blue Cross Blue Shield|Aetna|UnitedHealthcare|Cigna|Humana|Anthem|Kaiser)",
        ]
        
        for pattern in payer_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                contract_data["payer_name"] = match.group(1).strip()
                break
        
        # Date patterns
        date_patterns = [
            r"Effective\s*Date[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})",
            r"Effective[:\s]*(\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2})",
            r"(?:begins|commencing)[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})",
        ]
        
        for pattern in date_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                contract_data["effective_date"] = self._parse_date(match.group(1))
                break
        
        # Termination date patterns
        term_patterns = [
            r"(?:Termination|Expiration|End)\s*Date[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})",
            r"(?:terminates|expires|ends)[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})",
        ]
        
        for pattern in term_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                contract_data["termination_date"] = self._parse_date(match.group(1))
                break
        
        # Generate payer_id from payer_name
        if contract_data["payer_name"]:
            payer_abbrev = "".join([w[0] for w in contract_data["payer_name"].split()[:2]]).upper()
            contract_data["payer_id"] = f"{payer_abbrev}-001"
        
        return contract_data
    
    def _parse_date(self, date_str: str) -> Optional[str]:
        """Parse date string to ISO format."""
        
        date_formats = [
            "%m/%d/%Y",
            "%m-%d-%Y",
            "%Y/%m/%d",
            "%Y-%m-%d",
            "%m/%d/%y",
            "%m-%d-%y",
        ]
        
        for fmt in date_formats:
            try:
                dt = datetime.strptime(date_str.strip(), fmt)
                return dt.strftime("%Y-%m-%d")
            except ValueError:
                continue
        
        return None
    
    def _extract_rate_schedules(self, tables: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Extract rate schedules from parsed tables."""
        
        rate_schedules = []
        
        for table in tables:
            headers = [h.lower() for h in table.get("headers", [])]
            
            # Check if this looks like a rate table
            rate_indicators = ["rate", "amount", "fee", "price", "cpt", "service"]
            if not any(ind in " ".join(headers) for ind in rate_indicators):
                continue
            
            # Map columns
            col_map = {}
            for i, header in enumerate(headers):
                if "service" in header or "category" in header:
                    col_map["service_category"] = i
                elif "cpt" in header or "code" in header:
                    col_map["cpt_code"] = i
                elif "rate" in header or "amount" in header or "fee" in header:
                    col_map["rate_amount"] = i
                elif "type" in header:
                    col_map["rate_type"] = i
            
            # Extract rows
            for row in table.get("rows", []):
                schedule = {
                    "service_category": self._safe_get(row, col_map.get("service_category")),
                    "cpt_code": self._safe_get(row, col_map.get("cpt_code")),
                    "rate_type": self._safe_get(row, col_map.get("rate_type"), "FEE_SCHEDULE"),
                    "rate_amount": self._parse_amount(self._safe_get(row, col_map.get("rate_amount"))),
                    "effective_date": None,  # Will inherit from contract
                }
                
                if schedule["rate_amount"] is not None:
                    rate_schedules.append(schedule)
        
        return rate_schedules
    
    def _extract_amendments(self, text: str) -> List[Dict[str, Any]]:
        """Extract amendment information from text."""
        
        amendments = []
        
        # Amendment patterns
        amendment_pattern = r"Amendment\s*(?:#|No\.?)?\s*(\d+)[:\s]*(.*?)(?=Amendment|$)"
        
        for match in re.finditer(amendment_pattern, text, re.IGNORECASE | re.DOTALL):
            amendment_id = f"AMD-{match.group(1)}"
            description = match.group(2)[:500].strip()  # Limit description length
            
            # Try to find effective date in amendment text
            date_match = re.search(r"effective[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})", 
                                   description, re.IGNORECASE)
            
            amendment = {
                "amendment_id": amendment_id,
                "effective_date": self._parse_date(date_match.group(1)) if date_match else None,
                "description": description,
                "amendment_type": "MODIFICATION",
            }
            
            amendments.append(amendment)
        
        return amendments
    
    def _safe_get(self, lst: list, idx: Optional[int], default: Any = None) -> Any:
        """Safely get list element by index."""
        if idx is None or idx >= len(lst):
            return default
        return lst[idx]
    
    def _parse_amount(self, value: Any) -> Optional[float]:
        """Parse monetary amount from string."""
        if value is None:
            return None
        
        # Remove currency symbols and commas
        cleaned = re.sub(r"[$,]", "", str(value))
        
        try:
            return float(cleaned)
        except ValueError:
            return None
    
    def _calculate_confidence(self, contract_data: Dict[str, Any]) -> float:
        """
        Calculate extraction confidence score.
        
        Based on presence and validity of key fields.
        """
        score = 0.0
        weights = {
            "contract_id": 0.15,
            "payer_name": 0.15,
            "provider_npi": 0.20,
            "provider_name": 0.10,
            "effective_date": 0.15,
            "termination_date": 0.10,
            "rate_schedules": 0.15,
        }
        
        for field, weight in weights.items():
            value = contract_data.get(field)
            if value:
                if isinstance(value, list) and len(value) > 0:
                    score += weight
                elif not isinstance(value, list):
                    score += weight
        
        return round(score, 2)
