#!/bin/bash
# ==========================================
# Step 3: Configure S3 Event Notification
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

# Load SQS config from previous step
if [ -f /tmp/sqs_config.sh ]; then
    source /tmp/sqs_config.sh
else
    # Get SQS info if not available
    SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --query 'QueueUrl' --output text)
    SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$SQS_QUEUE_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
fi

echo -e "${YELLOW}Step 3: Configuring S3 Event Notifications...${NC}"

# Update SQS policy to allow S3 to send messages
echo "  Updating SQS policy for S3 notifications..."
aws sqs set-queue-attributes \
    --queue-url "$SQS_QUEUE_URL" \
    --attributes '{
        "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"s3.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"'"$SQS_QUEUE_ARN"'\",\"Condition\":{\"ArnLike\":{\"aws:SourceArn\":\"arn:aws:s3:::'"$S3_RAW_BUCKET"'\"}}}]}"
    }'

echo -e "  ${GREEN}✓ SQS policy updated${NC}"

# Configure S3 event notification
echo "  Setting up S3 event notification for .pdf files..."
aws s3api put-bucket-notification-configuration \
    --bucket "$S3_RAW_BUCKET" \
    --notification-configuration '{
        "QueueConfigurations": [{
            "QueueArn": "'"$SQS_QUEUE_ARN"'",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [{"Name": "suffix", "Value": ".pdf"}]
                }
            }
        }]
    }'

echo -e "  ${GREEN}✓ S3 event notification configured${NC}"
echo "  Bucket: $S3_RAW_BUCKET"
echo "  Trigger: *.pdf uploads"
echo "  Target:  $SQS_QUEUE_NAME"

echo -e "${GREEN}Step 3 Complete: S3 Event Notification Configured${NC}"
