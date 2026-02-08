#!/bin/bash
# ==========================================
# Step 1: Create S3 Buckets
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

S3_RAW_BUCKET="${PROJECT_NAME}-raw-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
S3_PROCESSED_BUCKET="${PROJECT_NAME}-processed-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 1: Creating S3 Buckets...${NC}"
echo "  Region: $AWS_REGION"
echo "  Account ID: $AWS_ACCOUNT_ID"

# Create raw bucket
echo ""
echo "Creating bucket: $S3_RAW_BUCKET"
if aws s3api head-bucket --bucket "$S3_RAW_BUCKET" 2>/dev/null; then
    echo -e "  ${GREEN}[OK] Bucket already exists${NC}"
else
    if [ "$AWS_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$S3_RAW_BUCKET" --region "$AWS_REGION" > /dev/null 2>&1
    else
        aws s3api create-bucket --bucket "$S3_RAW_BUCKET" --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION" > /dev/null 2>&1
    fi
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}[OK] Created bucket${NC}"
    else
        echo -e "  ${RED}[FAILED] Could not create bucket${NC}"
    fi
fi

# Create processed bucket
echo ""
echo "Creating bucket: $S3_PROCESSED_BUCKET"
if aws s3api head-bucket --bucket "$S3_PROCESSED_BUCKET" 2>/dev/null; then
    echo -e "  ${GREEN}[OK] Bucket already exists${NC}"
else
    if [ "$AWS_REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$S3_PROCESSED_BUCKET" --region "$AWS_REGION" > /dev/null 2>&1
    else
        aws s3api create-bucket --bucket "$S3_PROCESSED_BUCKET" --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION" > /dev/null 2>&1
    fi
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}[OK] Created bucket${NC}"
    else
        echo -e "  ${RED}[FAILED] Could not create bucket${NC}"
    fi
fi

# Create folder structure
echo ""
echo "Creating folder structure..."
aws s3api put-object --bucket "$S3_RAW_BUCKET" --key "incoming/" > /dev/null 2>&1
aws s3api put-object --bucket "$S3_PROCESSED_BUCKET" --key "contracts/" > /dev/null 2>&1
aws s3api put-object --bucket "$S3_PROCESSED_BUCKET" --key "rate_schedules/" > /dev/null 2>&1
aws s3api put-object --bucket "$S3_PROCESSED_BUCKET" --key "amendments/" > /dev/null 2>&1
echo -e "  ${GREEN}[OK] Folder structure created${NC}"

echo ""
echo -e "${GREEN}Step 1 Complete: S3 Buckets Created${NC}"
echo "  Raw Bucket: $S3_RAW_BUCKET"
echo "  Processed Bucket: $S3_PROCESSED_BUCKET"
