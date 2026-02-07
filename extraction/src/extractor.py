"""
PDF Contract Extraction Service

Main entry point for the extraction pipeline.
Triggered by S3 events when new PDFs arrive.
"""

import os
import json
import logging
from datetime import datetime
from typing import Optional

import boto3
import click
import structlog

from .docling_parser import DoclingParser
from .contract_schema import ContractData, validate_contract
from .s3_handler import S3Handler

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger(__name__)


class ContractExtractor:
    """
    Main extraction orchestrator.
    
    Coordinates the extraction pipeline:
    1. Download PDF from S3
    2. Parse with Docling
    3. Extract structured data
    4. Validate against schema
    5. Upload JSON to processed bucket
    """
    
    def __init__(
        self,
        raw_bucket: str,
        processed_bucket: str,
        aws_region: str = "us-east-1"
    ):
        self.raw_bucket = raw_bucket
        self.processed_bucket = processed_bucket
        self.s3_handler = S3Handler(aws_region)
        self.parser = DoclingParser()
        
        logger.info(
            "Initialized ContractExtractor",
            raw_bucket=raw_bucket,
            processed_bucket=processed_bucket
        )
    
    def process_pdf(self, s3_key: str) -> Optional[dict]:
        """
        Process a single PDF contract.
        
        Args:
            s3_key: S3 key of the PDF file
            
        Returns:
            Extracted contract data as dict, or None if extraction failed
        """
        logger.info("Processing PDF", s3_key=s3_key)
        
        try:
            # Download PDF to temp location
            local_path = self.s3_handler.download_file(
                self.raw_bucket, 
                s3_key
            )
            
            # Parse PDF with Docling
            extracted_data = self.parser.parse_contract(local_path)
            
            if extracted_data is None:
                logger.error("Failed to extract data from PDF", s3_key=s3_key)
                return None
            
            # Add metadata
            extracted_data["extraction_metadata"] = {
                "extracted_at": datetime.utcnow().isoformat() + "Z",
                "confidence_score": extracted_data.get("_confidence", 0.0),
                "source_file": s3_key,
                "extractor_version": "1.0.0"
            }
            
            # Remove internal fields
            extracted_data.pop("_confidence", None)
            
            # Validate against schema
            is_valid, errors = validate_contract(extracted_data)
            
            if not is_valid:
                logger.warning(
                    "Contract validation errors",
                    s3_key=s3_key,
                    errors=errors
                )
            
            # Generate output path with partitioning
            output_key = self._generate_output_key(extracted_data, s3_key)
            
            # Upload to processed bucket
            self.s3_handler.upload_json(
                self.processed_bucket,
                output_key,
                extracted_data
            )
            
            logger.info(
                "Successfully processed PDF",
                s3_key=s3_key,
                output_key=output_key,
                contract_id=extracted_data.get("contract_id")
            )
            
            return extracted_data
            
        except Exception as e:
            logger.exception(
                "Error processing PDF",
                s3_key=s3_key,
                error=str(e)
            )
            return None
        
        finally:
            # Cleanup temp file
            if 'local_path' in locals() and os.path.exists(local_path):
                os.remove(local_path)
    
    def _generate_output_key(self, data: dict, source_key: str) -> str:
        """
        Generate partitioned S3 output key.
        
        Format: contracts/payer={payer_id}/contract_date={YYYY-MM-DD}/{filename}.json
        """
        payer_id = data.get("payer_id", "unknown")
        effective_date = data.get("effective_date", datetime.utcnow().date().isoformat())
        
        # Extract filename without extension
        filename = os.path.basename(source_key).replace(".pdf", "").replace(".PDF", "")
        
        output_key = (
            f"contracts/"
            f"payer={payer_id}/"
            f"contract_date={effective_date}/"
            f"{filename}.json"
        )
        
        return output_key
    
    def process_s3_event(self, event: dict) -> list:
        """
        Process S3 event notification (Lambda/SQS trigger).
        
        Args:
            event: S3 event notification payload
            
        Returns:
            List of processed contract IDs
        """
        processed = []
        
        for record in event.get("Records", []):
            s3_info = record.get("s3", {})
            bucket = s3_info.get("bucket", {}).get("name")
            key = s3_info.get("object", {}).get("key")
            
            if bucket != self.raw_bucket:
                logger.warning(
                    "Ignoring event from unexpected bucket",
                    bucket=bucket,
                    expected=self.raw_bucket
                )
                continue
            
            if not key.lower().endswith(".pdf"):
                logger.info("Skipping non-PDF file", key=key)
                continue
            
            result = self.process_pdf(key)
            
            if result:
                processed.append(result.get("contract_id"))
        
        return processed


@click.command()
@click.option(
    "--raw-bucket",
    envvar="S3_RAW_BUCKET",
    required=True,
    help="S3 bucket for raw PDF contracts"
)
@click.option(
    "--processed-bucket",
    envvar="S3_PROCESSED_BUCKET",
    required=True,
    help="S3 bucket for processed JSON output"
)
@click.option(
    "--s3-key",
    default=None,
    help="Specific S3 key to process (for manual runs)"
)
@click.option(
    "--event-file",
    default=None,
    help="Path to S3 event JSON file (for batch processing)"
)
def main(raw_bucket: str, processed_bucket: str, s3_key: str, event_file: str):
    """
    PDF Contract Extraction Service
    
    Extracts structured data from healthcare provider contracts
    and outputs partitioned JSON to S3.
    """
    extractor = ContractExtractor(raw_bucket, processed_bucket)
    
    if s3_key:
        # Process single file
        result = extractor.process_pdf(s3_key)
        if result:
            click.echo(f"Processed: {result.get('contract_id')}")
        else:
            click.echo("Extraction failed", err=True)
            raise SystemExit(1)
            
    elif event_file:
        # Process from event file
        with open(event_file) as f:
            event = json.load(f)
        processed = extractor.process_s3_event(event)
        click.echo(f"Processed {len(processed)} contracts")
        
    else:
        click.echo("Specify --s3-key or --event-file", err=True)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
