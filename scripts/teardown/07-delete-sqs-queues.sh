#!/bin/bash
# ==========================================
# Teardown Step 7: Delete SQS Queues
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Teardown Step 7: Deleting SQS Queues...${NC}"

# Delete main queue
SQS_URL=$(aws sqs get-queue-url \
    --queue-name "$SQS_QUEUE_NAME" \
    --query 'QueueUrl' --output text 2>/dev/null || echo "")

if [ -n "$SQS_URL" ]; then
    aws sqs delete-queue --queue-url "$SQS_URL"
    echo -e "  ${GREEN}✓ Deleted $SQS_QUEUE_NAME${NC}"
else
    echo "  Queue $SQS_QUEUE_NAME not found, skipping..."
fi

# Delete dead letter queue
DLQ_URL=$(aws sqs get-queue-url \
    --queue-name "${SQS_QUEUE_NAME}-dlq" \
    --query 'QueueUrl' --output text 2>/dev/null || echo "")

if [ -n "$DLQ_URL" ]; then
    aws sqs delete-queue --queue-url "$DLQ_URL"
    echo -e "  ${GREEN}✓ Deleted ${SQS_QUEUE_NAME}-dlq${NC}"
else
    echo "  Queue ${SQS_QUEUE_NAME}-dlq not found, skipping..."
fi

echo -e "${GREEN}Teardown Step 7 Complete: SQS Queues Deleted${NC}"
