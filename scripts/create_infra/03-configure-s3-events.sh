#!/bin/bash
# ==========================================
# Step 3: Configure S3 Event Notifications
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

S3_RAW_BUCKET="${PROJECT_NAME}-raw-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
SQS_QUEUE_NAME="${PROJECT_NAME}-queue-${ENVIRONMENT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 3: Configuring S3 Event Notifications...${NC}"
echo "  Bucket: $S3_RAW_BUCKET"
echo "  Queue: $SQS_QUEUE_NAME"

# Get SQS Queue ARN
SQS_QUEUE_ARN="arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SQS_QUEUE_NAME}"
echo "  Queue ARN: $SQS_QUEUE_ARN"

# Update SQS policy to allow S3 to send messages
echo ""
echo "Updating SQS policy to allow S3 notifications..."

QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null)

POLICY="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"s3.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"${SQS_QUEUE_ARN}\",\"Condition\":{\"ArnLike\":{\"aws:SourceArn\":\"arn:aws:s3:::${S3_RAW_BUCKET}\"}}}]}"

aws sqs set-queue-attributes \
    --queue-url "$QUEUE_URL" \
    --attributes "{\"Policy\":$(echo $POLICY | jq -R '.')}" \
    --region "$AWS_REGION" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}[OK] SQS policy updated${NC}"
else
    echo -e "  ${YELLOW}[WARN] Could not update SQS policy${NC}"
fi

# Configure S3 event notification
echo ""
echo "Configuring S3 bucket notification..."

cat > /tmp/s3-notification.json << EOF
{
    "QueueConfigurations": [{
        "QueueArn": "${SQS_QUEUE_ARN}",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
            "Key": {
                "FilterRules": [
                    {"Name": "prefix", "Value": "incoming/"},
                    {"Name": "suffix", "Value": ".pdf"}
                ]
            }
        }
    }]
}
EOF

aws s3api put-bucket-notification-configuration \
    --bucket "$S3_RAW_BUCKET" \
    --notification-configuration file:///tmp/s3-notification.json \
    --region "$AWS_REGION" 2>&1

if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}[OK] S3 notification configured${NC}"
else
    echo -e "  ${RED}[FAILED] Could not configure S3 notification${NC}"
fi

echo ""
echo -e "${GREEN}Step 3 Complete: S3 Event Notifications Configured${NC}"
echo "  PDFs uploaded to s3://${S3_RAW_BUCKET}/incoming/ will trigger SQS messages"
