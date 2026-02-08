#!/bin/bash
# ==========================================
# Step 10: Display Infrastructure Summary
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Derived names
S3_RAW_BUCKET="${PROJECT_NAME}-raw-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
S3_PROCESSED_BUCKET="${PROJECT_NAME}-processed-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
ECR_REPO_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
ECS_CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
SQS_QUEUE_NAME="${PROJECT_NAME}-queue-${ENVIRONMENT}"
REDSHIFT_WORKGROUP="${PROJECT_NAME}-workgroup-${ENVIRONMENT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=========================================="
echo -e "${GREEN}Infrastructure Summary${NC}"
echo "=========================================="
echo ""
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"
echo ""

# S3 Buckets
echo "--- S3 Buckets ---"
echo "  Raw:       s3://${S3_RAW_BUCKET}"
echo "  Processed: s3://${S3_PROCESSED_BUCKET}"
echo ""

# SQS Queue
echo "--- SQS Queue ---"
QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --region "$AWS_REGION" --query 'QueueUrl' --output text 2>/dev/null || echo "Not found")
echo "  Queue URL: $QUEUE_URL"
echo ""

# ECR Repository
echo "--- ECR Repository ---"
ECR_URI=$(aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$AWS_REGION" --query 'repositories[0].repositoryUri' --output text 2>/dev/null || echo "Not found")
echo "  Repository: $ECR_URI"
echo ""

# ECS Cluster
echo "--- ECS Cluster ---"
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$ECS_CLUSTER_NAME" --region "$AWS_REGION" --query 'clusters[0].status' --output text 2>/dev/null || echo "Not found")
echo "  Cluster: $ECS_CLUSTER_NAME"
echo "  Status: $CLUSTER_STATUS"
echo ""

# Redshift
echo "--- Redshift Serverless ---"
REDSHIFT_ENDPOINT=$(aws redshift-serverless get-workgroup --workgroup-name "$REDSHIFT_WORKGROUP" --region "$AWS_REGION" --query 'workgroup.endpoint.address' --output text 2>/dev/null || echo "Not found")
REDSHIFT_STATUS=$(aws redshift-serverless get-workgroup --workgroup-name "$REDSHIFT_WORKGROUP" --region "$AWS_REGION" --query 'workgroup.status' --output text 2>/dev/null || echo "Not found")
echo "  Host: $REDSHIFT_ENDPOINT"
echo "  Port: 5439"
echo "  Database: contracts_dw"
echo "  User: admin"
echo "  Status: $REDSHIFT_STATUS"
echo ""

# IAM Roles
echo "--- IAM Roles ---"
echo "  Task Role:      arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-ecs-task-role"
echo "  Execution Role: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-ecs-execution-role"
echo ""

# CloudWatch
echo "--- CloudWatch Logs ---"
echo "  Log Group: /ecs/${PROJECT_NAME}-${ENVIRONMENT}"
echo ""

echo "=========================================="
echo -e "${GREEN}Next Steps${NC}"
echo "=========================================="
echo ""
echo "1. Build and push Docker image (on local machine):"
echo "   aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI"
echo "   cd extraction"
echo "   docker build -t $ECR_REPO_NAME ."
echo "   docker tag $ECR_REPO_NAME:latest $ECR_URI:latest"
echo "   docker push $ECR_URI:latest"
echo ""
echo "2. Create ECS Service:"
echo "   bash 11-create-ecs-service.sh"
echo ""
echo "3. Test the pipeline:"
echo "   aws s3 cp sample.pdf s3://${S3_RAW_BUCKET}/incoming/"
echo ""
echo "4. Monitor logs:"
echo "   aws logs tail /ecs/${PROJECT_NAME}-${ENVIRONMENT} --follow"
echo ""
echo -e "${GREEN}Step 10 Complete: Summary Displayed${NC}"
