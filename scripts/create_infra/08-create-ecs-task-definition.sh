#!/bin/bash
# ==========================================
# Step 8: Register ECS Task Definition
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Derived names
ECR_REPO_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
ECS_TASK_FAMILY="${PROJECT_NAME}-task"
S3_RAW_BUCKET="${PROJECT_NAME}-raw-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
S3_PROCESSED_BUCKET="${PROJECT_NAME}-processed-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
SQS_QUEUE_NAME="${PROJECT_NAME}-queue-${ENVIRONMENT}"
SQS_QUEUE_URL="https://sqs.${AWS_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/${SQS_QUEUE_NAME}"
LOG_GROUP_NAME="/ecs/${PROJECT_NAME}-${ENVIRONMENT}"
IAM_TASK_ROLE="${PROJECT_NAME}-ecs-task-role"
IAM_EXECUTION_ROLE="${PROJECT_NAME}-ecs-execution-role"
ECR_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_EXECUTION_ROLE}"
TASK_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_TASK_ROLE}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 8: Registering ECS Task Definition...${NC}"
echo "  Region: $AWS_REGION"
echo "  Account ID: $AWS_ACCOUNT_ID"
echo "  Task Family: $ECS_TASK_FAMILY"
echo "  ECR Repository: $ECR_REPO_URI"
echo "  SQS Queue URL: $SQS_QUEUE_URL"
echo "  Task Role: $TASK_ROLE_ARN"
echo "  Execution Role: $EXECUTION_ROLE_ARN"

# Create task definition JSON
echo ""
echo "Creating task definition..."

cat > /tmp/task-definition.json << EOF
{
    "family": "${ECS_TASK_FAMILY}",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "512",
    "memory": "1024",
    "executionRoleArn": "${EXECUTION_ROLE_ARN}",
    "taskRoleArn": "${TASK_ROLE_ARN}",
    "containerDefinitions": [{
        "name": "extractor",
        "image": "${ECR_REPO_URI}:latest",
        "essential": true,
        "command": ["--poll"],
        "environment": [
            {"name": "S3_RAW_BUCKET", "value": "${S3_RAW_BUCKET}"},
            {"name": "S3_PROCESSED_BUCKET", "value": "${S3_PROCESSED_BUCKET}"},
            {"name": "SQS_QUEUE_URL", "value": "${SQS_QUEUE_URL}"},
            {"name": "AWS_REGION", "value": "${AWS_REGION}"}
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "${LOG_GROUP_NAME}",
                "awslogs-region": "${AWS_REGION}",
                "awslogs-stream-prefix": "extractor"
            }
        }
    }]
}
EOF

# Register task definition
REGISTER_RESULT=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/task-definition.json \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text 2>&1)

if [ $? -eq 0 ] && [ -n "$REGISTER_RESULT" ] && [ "$REGISTER_RESULT" != "None" ]; then
    echo -e "  ${GREEN}[OK] Registered ECS Task Definition${NC}"
    echo "  Task Definition ARN: $REGISTER_RESULT"
    
    echo ""
    echo "  Task Family: $ECS_TASK_FAMILY"
    echo "  CPU: 512 (0.5 vCPU)"
    echo "  Memory: 1024 MB"
    echo "  Image: $ECR_REPO_URI:latest"
    echo "  Command: --poll (polls SQS for messages)"
    echo ""
    echo -e "${GREEN}Step 8 Complete: ECS Task Definition Registered${NC}"
else
    echo -e "  ${RED}[FAILED] Could not register task definition${NC}"
    echo "  Error: $REGISTER_RESULT"
fi
