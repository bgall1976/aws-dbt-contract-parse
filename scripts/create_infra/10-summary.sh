#!/bin/bash
# ==========================================
# Step 10: Display Summary and Save Config
# ==========================================

# Load configuration
source "$(dirname "$0")/00-config.sh"

# Load all saved configs
[ -f /tmp/sqs_config.sh ] && source /tmp/sqs_config.sh
[ -f /tmp/ecr_config.sh ] && source /tmp/ecr_config.sh
[ -f /tmp/iam_config.sh ] && source /tmp/iam_config.sh
[ -f /tmp/redshift_config.sh ] && source /tmp/redshift_config.sh

# Get values if not loaded
if [ -z "$ECR_REPO_URI" ]; then
    ECR_REPO_URI=$(aws ecr describe-repositories \
        --repository-names "$ECR_REPO_NAME" \
        --query 'repositories[0].repositoryUri' --output text 2>/dev/null || echo "not-found")
fi

if [ -z "$REDSHIFT_HOST" ]; then
    REDSHIFT_HOST=$(aws redshift-serverless get-workgroup \
        --workgroup-name "$REDSHIFT_WORKGROUP" \
        --query 'workgroup.endpoint.address' --output text 2>/dev/null || echo "not-found")
fi

if [ -z "$SQS_QUEUE_URL" ]; then
    SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --query 'QueueUrl' --output text 2>/dev/null || echo "not-found")
fi

echo ""
echo -e "${GREEN}=========================================="
echo "Infrastructure Setup Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Resources Created:"
echo "  S3 Raw Bucket:        $S3_RAW_BUCKET"
echo "  S3 Processed Bucket:  $S3_PROCESSED_BUCKET"
echo "  SQS Queue:            $SQS_QUEUE_NAME"
echo "  ECR Repository:       $ECR_REPO_URI"
echo "  ECS Cluster:          $ECS_CLUSTER_NAME"
echo "  ECS Task Family:      $ECS_TASK_FAMILY"
echo "  Redshift Namespace:   $REDSHIFT_NAMESPACE"
echo "  Redshift Workgroup:   $REDSHIFT_WORKGROUP"
echo ""
echo "Redshift Connection Info:"
echo "  Host:     $REDSHIFT_HOST"
echo "  Port:     5439"
echo "  Database: $REDSHIFT_DATABASE"
echo "  User:     $REDSHIFT_ADMIN_USER"
echo ""

# Save full configuration to file
CONFIG_FILE="/tmp/pipeline-config.env"
cat > "$CONFIG_FILE" << EOF
# ==========================================
# Contract Pipeline Configuration
# Generated: $(date)
# ==========================================

# Project
export PROJECT_NAME="${PROJECT_NAME}"
export AWS_REGION="${AWS_REGION}"
export ENVIRONMENT="${ENVIRONMENT}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"

# S3
export S3_RAW_BUCKET="${S3_RAW_BUCKET}"
export S3_PROCESSED_BUCKET="${S3_PROCESSED_BUCKET}"

# SQS
export SQS_QUEUE_URL="${SQS_QUEUE_URL}"
export SQS_QUEUE_NAME="${SQS_QUEUE_NAME}"

# ECR
export ECR_REPO_URI="${ECR_REPO_URI}"
export ECR_REPO_NAME="${ECR_REPO_NAME}"

# ECS
export ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME}"
export ECS_TASK_FAMILY="${ECS_TASK_FAMILY}"

# Redshift
export REDSHIFT_HOST="${REDSHIFT_HOST}"
export REDSHIFT_PORT="5439"
export REDSHIFT_USER="${REDSHIFT_ADMIN_USER}"
# REDSHIFT_PASSWORD not saved for security - use environment variable
export REDSHIFT_DATABASE="${REDSHIFT_DATABASE}"

# IAM
export IAM_ROLE_NAME="${IAM_ROLE_NAME}"
export IAM_EXECUTION_ROLE_NAME="${IAM_EXECUTION_ROLE_NAME}"
EOF

echo "Configuration saved to: $CONFIG_FILE"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Load environment variables:"
echo "   source $CONFIG_FILE"
echo ""
echo "2. Build and push Docker image:"
echo "   aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI"
echo "   docker build -t $ECR_REPO_NAME ./extraction"
echo "   docker tag $ECR_REPO_NAME:latest $ECR_REPO_URI:latest"
echo "   docker push $ECR_REPO_URI:latest"
echo ""
echo "3. Upload a test PDF:"
echo "   aws s3 cp sample_contract.pdf s3://$S3_RAW_BUCKET/incoming/"
echo ""
echo "4. Set up dbt (copy these to your local machine):"
echo "   export REDSHIFT_HOST=$REDSHIFT_HOST"
echo "   export REDSHIFT_PORT=5439"
echo "   export REDSHIFT_USER=$REDSHIFT_ADMIN_USER"
echo "   export REDSHIFT_PASSWORD='<your-password-here>'"
echo "   export REDSHIFT_DATABASE=$REDSHIFT_DATABASE"
echo ""
