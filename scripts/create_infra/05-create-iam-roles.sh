#!/bin/bash
# ==========================================
# Step 5: Create IAM Roles for ECS
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

IAM_TASK_ROLE="${PROJECT_NAME}-ecs-task-role"
IAM_EXECUTION_ROLE="${PROJECT_NAME}-ecs-execution-role"
S3_RAW_BUCKET="${PROJECT_NAME}-raw-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
S3_PROCESSED_BUCKET="${PROJECT_NAME}-processed-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
SQS_QUEUE_NAME="${PROJECT_NAME}-queue-${ENVIRONMENT}"
LOG_GROUP_NAME="/ecs/${PROJECT_NAME}-${ENVIRONMENT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 5: Creating IAM Roles...${NC}"
echo "  Region: $AWS_REGION"
echo "  Account ID: $AWS_ACCOUNT_ID"

# Create trust policy for ECS
cat > /tmp/ecs-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {
            "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
    }]
}
EOF

# ==========================================
# Create ECS Task Execution Role
# ==========================================
echo ""
echo "Creating ECS Task Execution Role: $IAM_EXECUTION_ROLE"

EXEC_ROLE_EXISTS=$(aws iam get-role --role-name "$IAM_EXECUTION_ROLE" --query 'Role.Arn' --output text 2>/dev/null)

if [ -n "$EXEC_ROLE_EXISTS" ] && [ "$EXEC_ROLE_EXISTS" != "None" ]; then
    echo -e "  ${GREEN}[OK] Execution role already exists${NC}"
else
    aws iam create-role \
        --role-name "$IAM_EXECUTION_ROLE" \
        --assume-role-policy-document file:///tmp/ecs-trust-policy.json \
        --description "ECS task execution role for $PROJECT_NAME" \
        --output text > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}[OK] Created execution role${NC}"
    else
        echo -e "  ${RED}[FAILED] Could not create execution role${NC}"
    fi

    aws iam attach-role-policy \
        --role-name "$IAM_EXECUTION_ROLE" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
        --output text > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}[OK] Attached ECS execution policy${NC}"
    else
        echo -e "  ${RED}[FAILED] Could not attach execution policy${NC}"
    fi
fi

# ==========================================
# Create ECS Task Role
# ==========================================
echo ""
echo "Creating ECS Task Role: $IAM_TASK_ROLE"

TASK_ROLE_EXISTS=$(aws iam get-role --role-name "$IAM_TASK_ROLE" --query 'Role.Arn' --output text 2>/dev/null)

if [ -n "$TASK_ROLE_EXISTS" ] && [ "$TASK_ROLE_EXISTS" != "None" ]; then
    echo -e "  ${GREEN}[OK] Task role already exists${NC}"
else
    aws iam create-role \
        --role-name "$IAM_TASK_ROLE" \
        --assume-role-policy-document file:///tmp/ecs-trust-policy.json \
        --description "ECS task role for $PROJECT_NAME application" \
        --output text > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}[OK] Created task role${NC}"
    else
        echo -e "  ${RED}[FAILED] Could not create task role${NC}"
    fi
fi

# ==========================================
# Create and attach custom policy
# ==========================================
echo ""
echo "Creating custom policy for S3 and SQS access..."

POLICY_NAME="${PROJECT_NAME}-task-policy"

cat > /tmp/task-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_RAW_BUCKET}",
                "arn:aws:s3:::${S3_RAW_BUCKET}/*",
                "arn:aws:s3:::${S3_PROCESSED_BUCKET}",
                "arn:aws:s3:::${S3_PROCESSED_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes",
                "sqs:GetQueueUrl"
            ],
            "Resource": "arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SQS_QUEUE_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}:*"
        }
    ]
}
EOF

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
POLICY_EXISTS=$(aws iam get-policy --policy-arn "$POLICY_ARN" --query 'Policy.Arn' --output text 2>/dev/null)

if [ -n "$POLICY_EXISTS" ] && [ "$POLICY_EXISTS" != "None" ]; then
    echo -e "  ${GREEN}[OK] Policy already exists${NC}"
else
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/task-policy.json \
        --description "Custom policy for $PROJECT_NAME ECS tasks" \
        --output text > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}[OK] Created custom policy${NC}"
    else
        echo -e "  ${RED}[FAILED] Could not create custom policy${NC}"
    fi
fi

# Attach custom policy to task role
aws iam attach-role-policy \
    --role-name "$IAM_TASK_ROLE" \
    --policy-arn "$POLICY_ARN" \
    --output text > /dev/null 2>&1

echo -e "  ${GREEN}[OK] Attached custom policy to task role${NC}"

# ==========================================
# Summary
# ==========================================
echo ""
echo "=========================================="
echo "IAM Roles Summary"
echo "=========================================="
echo "  Execution Role: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_EXECUTION_ROLE}"
echo "  Task Role:      arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_TASK_ROLE}"
echo "  Custom Policy:  arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
echo ""
echo -e "${GREEN}Step 5 Complete: IAM Roles Created${NC}"
