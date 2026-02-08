#!/bin/bash
# ==========================================
# PDF Contract Pipeline - Shared Configuration
# ==========================================
# Note: All scripts now work standalone with inline config.
# This file can be sourced for convenience but is not required.
# ==========================================

# ==========================================
# Configuration - EDIT THESE VALUES
# ==========================================
export PROJECT_NAME="contract-pipeline"
export AWS_REGION="us-east-2"
export ENVIRONMENT="dev"

# Redshift credentials
export REDSHIFT_ADMIN_USER="admin"
export REDSHIFT_DATABASE="contracts_dw"

# IMPORTANT: Set password via environment variable before running scripts:
#   export REDSHIFT_ADMIN_PASSWORD='YourSecurePassword123!'

# ==========================================
# Derived names (auto-generated)
# ==========================================
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
export S3_RAW_BUCKET="${PROJECT_NAME}-raw-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
export S3_PROCESSED_BUCKET="${PROJECT_NAME}-processed-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
export ECR_REPO_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
export ECS_CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
export ECS_SERVICE_NAME="contract-extractor"
export ECS_TASK_FAMILY="${PROJECT_NAME}-task"
export SQS_QUEUE_NAME="${PROJECT_NAME}-queue-${ENVIRONMENT}"
export REDSHIFT_NAMESPACE="${PROJECT_NAME}-${ENVIRONMENT}"
export REDSHIFT_WORKGROUP="${PROJECT_NAME}-workgroup-${ENVIRONMENT}"
export IAM_TASK_ROLE="${PROJECT_NAME}-ecs-task-role"
export IAM_EXECUTION_ROLE="${PROJECT_NAME}-ecs-execution-role"
export LOG_GROUP_NAME="/ecs/${PROJECT_NAME}-${ENVIRONMENT}"
export SECURITY_GROUP_NAME="${PROJECT_NAME}-redshift-sg"

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

echo -e "${GREEN}Configuration Loaded${NC}"
echo "  Project:     ${PROJECT_NAME}"
echo "  Region:      ${AWS_REGION}"
echo "  Environment: ${ENVIRONMENT}"
echo "  Account ID:  ${AWS_ACCOUNT_ID}"
echo ""
