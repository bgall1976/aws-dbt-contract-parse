#!/bin/bash
# ==========================================
# Step 8: Register ECS Task Definition
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

# Load saved configs
[ -f /tmp/ecr_config.sh ] && source /tmp/ecr_config.sh
[ -f /tmp/iam_config.sh ] && source /tmp/iam_config.sh

# Get ECR URI if not loaded
if [ -z "$ECR_REPO_URI" ]; then
    ECR_REPO_URI=$(aws ecr describe-repositories \
        --repository-names "$ECR_REPO_NAME" \
        --query 'repositories[0].repositoryUri' --output text)
fi

# Get role ARNs if not loaded
if [ -z "$TASK_ROLE_ARN" ]; then
    TASK_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
fi
if [ -z "$EXECUTION_ROLE_ARN" ]; then
    EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_EXECUTION_ROLE_NAME}"
fi

echo -e "${YELLOW}Step 8: Registering ECS Task Definition...${NC}"

# Create task definition JSON
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
        "environment": [
            {"name": "S3_RAW_BUCKET", "value": "${S3_RAW_BUCKET}"},
            {"name": "S3_PROCESSED_BUCKET", "value": "${S3_PROCESSED_BUCKET}"},
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
aws ecs register-task-definition \
    --cli-input-json file:///tmp/task-definition.json \
    > /dev/null

echo -e "  ${GREEN}✓ Registered ECS Task Definition${NC}"
echo "  Task Family: $ECS_TASK_FAMILY"
echo "  CPU: 512 (0.5 vCPU)"
echo "  Memory: 1024 MB"
echo "  Image: $ECR_REPO_URI:latest"

echo ""
echo "Note: You must push a Docker image to ECR before running tasks."

echo -e "${GREEN}Step 8 Complete: ECS Task Definition Registered${NC}"
