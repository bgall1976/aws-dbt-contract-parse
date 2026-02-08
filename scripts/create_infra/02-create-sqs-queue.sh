#!/bin/bash
# ==========================================
# Step 2: Create SQS Queue
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

SQS_QUEUE_NAME="${PROJECT_NAME}-queue-${ENVIRONMENT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 2: Creating SQS Queue...${NC}"
echo "  Region: $AWS_REGION"
echo "  Queue Name: $SQS_QUEUE_NAME"

# Check if queue exists
QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null)

if [ -n "$QUEUE_URL" ] && [ "$QUEUE_URL" != "None" ]; then
    echo -e "  ${GREEN}[OK] Queue already exists${NC}"
    echo "  Queue URL: $QUEUE_URL"
else
    echo "  Creating queue..."
    QUEUE_URL=$(aws sqs create-queue \
        --queue-name "$SQS_QUEUE_NAME" \
        --region "$AWS_REGION" \
        --attributes VisibilityTimeout=300,MessageRetentionPeriod=1209600,ReceiveMessageWaitTimeSeconds=20 \
        --query 'QueueUrl' --output text 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$QUEUE_URL" ]; then
        echo -e "  ${GREEN}[OK] Created queue${NC}"
        echo "  Queue URL: $QUEUE_URL"
    else
        echo -e "  ${RED}[FAILED] Could not create queue${NC}"
        echo "  Error: $QUEUE_URL"
    fi
fi

echo ""
echo -e "${GREEN}Step 2 Complete: SQS Queue Created${NC}"
