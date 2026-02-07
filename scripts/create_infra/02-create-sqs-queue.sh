#!/bin/bash
# ==========================================
# Step 2: Create SQS Queue
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Step 2: Creating SQS Queue...${NC}"

# Check if queue exists
queue_exists() {
    aws sqs get-queue-url --queue-name "$1" 2>/dev/null && return 0 || return 1
}

if queue_exists "$SQS_QUEUE_NAME"; then
    echo "  SQS queue $SQS_QUEUE_NAME already exists, skipping..."
    export SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --query 'QueueUrl' --output text)
else
    echo "  Creating SQS queue: $SQS_QUEUE_NAME"
    
    # Create dead letter queue first
    DLQ_URL=$(aws sqs create-queue \
        --queue-name "${SQS_QUEUE_NAME}-dlq" \
        --query 'QueueUrl' --output text)
    
    DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$DLQ_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    echo "  Created DLQ: ${SQS_QUEUE_NAME}-dlq"
    
    # Create main queue with DLQ
    export SQS_QUEUE_URL=$(aws sqs create-queue \
        --queue-name "$SQS_QUEUE_NAME" \
        --attributes '{
            "VisibilityTimeout": "900",
            "MessageRetentionPeriod": "86400",
            "RedrivePolicy": "{\"deadLetterTargetArn\":\"'"$DLQ_ARN"'\",\"maxReceiveCount\":\"3\"}"
        }' \
        --query 'QueueUrl' --output text)
    
    echo -e "  ${GREEN}✓ Created $SQS_QUEUE_NAME${NC}"
fi

# Get queue ARN
export SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
    --queue-url "$SQS_QUEUE_URL" \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' --output text)

echo "  Queue URL: $SQS_QUEUE_URL"
echo "  Queue ARN: $SQS_QUEUE_ARN"

# Save to temp file for other scripts
echo "export SQS_QUEUE_URL=\"$SQS_QUEUE_URL\"" > /tmp/sqs_config.sh
echo "export SQS_QUEUE_ARN=\"$SQS_QUEUE_ARN\"" >> /tmp/sqs_config.sh

echo -e "${GREEN}Step 2 Complete: SQS Queue Created${NC}"
