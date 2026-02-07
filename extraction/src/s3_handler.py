"""
S3 Handler

Manages S3 read/write operations for the extraction pipeline.
"""

import json
import os
import tempfile
from typing import Optional

import boto3
from botocore.exceptions import ClientError
import structlog

logger = structlog.get_logger(__name__)


class S3Handler:
    """
    Handler for S3 operations.
    
    Provides methods for downloading PDFs and uploading JSON results.
    """
    
    def __init__(self, region: str = "us-east-1"):
        """
        Initialize S3 handler.
        
        Args:
            region: AWS region for S3 operations
        """
        self.region = region
        self.s3_client = boto3.client('s3', region_name=region)
        logger.info("S3Handler initialized", region=region)
    
    def download_file(self, bucket: str, key: str, local_path: Optional[str] = None) -> str:
        """
        Download file from S3 to local filesystem.
        
        Args:
            bucket: S3 bucket name
            key: S3 object key
            local_path: Optional local path (generates temp file if not provided)
            
        Returns:
            Path to downloaded file
        """
        if local_path is None:
            # Create temp file with same extension
            ext = os.path.splitext(key)[1]
            fd, local_path = tempfile.mkstemp(suffix=ext)
            os.close(fd)
        
        logger.info("Downloading from S3", bucket=bucket, key=key, local_path=local_path)
        
        try:
            self.s3_client.download_file(bucket, key, local_path)
            logger.info("Download complete", local_path=local_path)
            return local_path
            
        except ClientError as e:
            logger.error(
                "Failed to download from S3",
                bucket=bucket,
                key=key,
                error=str(e)
            )
            raise
    
    def upload_file(self, bucket: str, key: str, local_path: str, content_type: str = None):
        """
        Upload file to S3.
        
        Args:
            bucket: S3 bucket name
            key: S3 object key
            local_path: Path to local file
            content_type: Optional content type header
        """
        logger.info("Uploading to S3", bucket=bucket, key=key)
        
        extra_args = {}
        if content_type:
            extra_args['ContentType'] = content_type
        
        try:
            self.s3_client.upload_file(
                local_path, 
                bucket, 
                key,
                ExtraArgs=extra_args if extra_args else None
            )
            logger.info("Upload complete", bucket=bucket, key=key)
            
        except ClientError as e:
            logger.error(
                "Failed to upload to S3",
                bucket=bucket,
                key=key,
                error=str(e)
            )
            raise
    
    def upload_json(self, bucket: str, key: str, data: dict):
        """
        Upload JSON data to S3.
        
        Args:
            bucket: S3 bucket name
            key: S3 object key
            data: Dictionary to serialize as JSON
        """
        logger.info("Uploading JSON to S3", bucket=bucket, key=key)
        
        try:
            json_bytes = json.dumps(data, indent=2, default=str).encode('utf-8')
            
            self.s3_client.put_object(
                Bucket=bucket,
                Key=key,
                Body=json_bytes,
                ContentType='application/json'
            )
            
            logger.info(
                "JSON upload complete",
                bucket=bucket,
                key=key,
                size_bytes=len(json_bytes)
            )
            
        except ClientError as e:
            logger.error(
                "Failed to upload JSON to S3",
                bucket=bucket,
                key=key,
                error=str(e)
            )
            raise
    
    def read_json(self, bucket: str, key: str) -> dict:
        """
        Read JSON file from S3.
        
        Args:
            bucket: S3 bucket name
            key: S3 object key
            
        Returns:
            Parsed JSON data as dictionary
        """
        logger.info("Reading JSON from S3", bucket=bucket, key=key)
        
        try:
            response = self.s3_client.get_object(Bucket=bucket, Key=key)
            content = response['Body'].read().decode('utf-8')
            data = json.loads(content)
            
            logger.info("JSON read complete", bucket=bucket, key=key)
            return data
            
        except ClientError as e:
            logger.error(
                "Failed to read JSON from S3",
                bucket=bucket,
                key=key,
                error=str(e)
            )
            raise
    
    def list_objects(self, bucket: str, prefix: str = "", suffix: str = "") -> list:
        """
        List objects in S3 bucket with optional prefix/suffix filtering.
        
        Args:
            bucket: S3 bucket name
            prefix: Key prefix filter
            suffix: Key suffix filter (e.g., ".pdf")
            
        Returns:
            List of matching S3 keys
        """
        logger.info("Listing S3 objects", bucket=bucket, prefix=prefix)
        
        keys = []
        paginator = self.s3_client.get_paginator('list_objects_v2')
        
        try:
            for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
                for obj in page.get('Contents', []):
                    key = obj['Key']
                    if suffix and not key.endswith(suffix):
                        continue
                    keys.append(key)
            
            logger.info(
                "List complete",
                bucket=bucket,
                prefix=prefix,
                count=len(keys)
            )
            return keys
            
        except ClientError as e:
            logger.error(
                "Failed to list S3 objects",
                bucket=bucket,
                prefix=prefix,
                error=str(e)
            )
            raise
    
    def object_exists(self, bucket: str, key: str) -> bool:
        """
        Check if an object exists in S3.
        
        Args:
            bucket: S3 bucket name
            key: S3 object key
            
        Returns:
            True if object exists, False otherwise
        """
        try:
            self.s3_client.head_object(Bucket=bucket, Key=key)
            return True
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                return False
            raise
    
    def delete_object(self, bucket: str, key: str):
        """
        Delete an object from S3.
        
        Args:
            bucket: S3 bucket name
            key: S3 object key
        """
        logger.info("Deleting S3 object", bucket=bucket, key=key)
        
        try:
            self.s3_client.delete_object(Bucket=bucket, Key=key)
            logger.info("Delete complete", bucket=bucket, key=key)
            
        except ClientError as e:
            logger.error(
                "Failed to delete S3 object",
                bucket=bucket,
                key=key,
                error=str(e)
            )
            raise
