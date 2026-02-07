#!/bin/bash
# ==========================================
# Step 1: Create S3 Buckets
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Step 1: Creating S3 Buckets...${NC}"

# Function to check if bucket exists
bucket_exists() {
    aws s3api head-bucket --bucket "$1" 2>/dev/null && return 0 || return 1
}

# Raw bucket
if bucket_exists "$S3_RAW_BUCKET"; then
    echo "  S3 bucket $S3_RAW_BUCKET already exists, skipping..."
else
    echo "  Creating S3 bucket: $S3_RAW_BUCKET"
    
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$S3_RAW_BUCKET" \
            --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$S3_RAW_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$S3_RAW_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$S3_RAW_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
        }'
    
    echo -e "  ${GREEN}✓ Created $S3_RAW_BUCKET${NC}"
fi

# Processed bucket
if bucket_exists "$S3_PROCESSED_BUCKET"; then
    echo "  S3 bucket $S3_PROCESSED_BUCKET already exists, skipping..."
else
    echo "  Creating S3 bucket: $S3_PROCESSED_BUCKET"
    
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$S3_PROCESSED_BUCKET" \
            --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$S3_PROCESSED_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$S3_PROCESSED_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$S3_PROCESSED_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
        }'
    
    echo -e "  ${GREEN}✓ Created $S3_PROCESSED_BUCKET${NC}"
fi

echo -e "${GREEN}Step 1 Complete: S3 Buckets Created${NC}"
