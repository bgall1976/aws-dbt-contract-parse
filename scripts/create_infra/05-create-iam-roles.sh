#!/bin/bash
# ==========================================
# Step 5: Create IAM Roles
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

# Load SQS config
if [ -f /tmp/sqs_config.sh ]; then
    source /tmp/sqs_config.sh
else
    SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --query 'QueueUrl' --output text 2>/dev/null || echo "")
    if [ -n "$SQS_QUEUE_URL" ]; then
        SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
            --queue-url "$SQS_QUEUE_URL" \
            --attribute-names QueueArn \
            --query 'Attributes.QueueArn' --output text)
    fi
fi

echo -e "${YELLOW}Step 5: Creating IAM Roles...${NC}"

# Check if role exists
role_exists() {
    aws iam get-role --role-name "$1" 2>/dev/null && return 0 || return 1
}

# ==========================================
# ECS Task Execution Role
# ==========================================
if role_exists "$IAM_EXECUTION_ROLE_NAME"; then
    echo "  IAM role $IAM_EXECUTION_ROLE_NAME already exists, skipping..."
else
    echo "  Creating ECS Task Execution Role: $IAM_EXECUTION_ROLE_NAME"
    
    aws iam create-role \
        --role-name "$IAM_EXECUTION_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "ecs-tasks.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }'
    
    aws iam attach-role-policy \
        --role-name "$IAM_EXECUTION_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    
    echo -e "  ${GREEN}✓ Created ECS Execution Role${NC}"
fi

# ==========================================
# ECS Task Role (application permissions)
# ==========================================
if role_exists "$IAM_ROLE_NAME"; then
    echo "  IAM role $IAM_ROLE_NAME already exists, skipping..."
else
    echo "  Creating ECS Task Role: $IAM_ROLE_NAME"
    
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "ecs-tasks.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }'
    
    # Create and attach custom policy for S3 and SQS access
    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name "ContractPipelineAccess" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["s3:GetObject", "s3:ListBucket"],
                    "Resource": [
                        "arn:aws:s3:::'"$S3_RAW_BUCKET"'",
                        "arn:aws:s3:::'"$S3_RAW_BUCKET"'/*"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
                    "Resource": [
                        "arn:aws:s3:::'"$S3_PROCESSED_BUCKET"'",
                        "arn:aws:s3:::'"$S3_PROCESSED_BUCKET"'/*"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
                    "Resource": "'"$SQS_QUEUE_ARN"'"
                },
                {
                    "Effect": "Allow",
                    "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
                    "Resource": "*"
                }
            ]
        }'
    
    echo -e "  ${GREEN}✓ Created ECS Task Role${NC}"
fi

# Save role ARNs
TASK_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_EXECUTION_ROLE_NAME}"

echo "  Task Role ARN:      $TASK_ROLE_ARN"
echo "  Execution Role ARN: $EXECUTION_ROLE_ARN"

# Save for other scripts
echo "export TASK_ROLE_ARN=\"$TASK_ROLE_ARN\"" > /tmp/iam_config.sh
echo "export EXECUTION_ROLE_ARN=\"$EXECUTION_ROLE_ARN\"" >> /tmp/iam_config.sh

echo -e "${GREEN}Step 5 Complete: IAM Roles Created${NC}"
