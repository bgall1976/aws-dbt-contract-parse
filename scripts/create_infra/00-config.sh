#!/bin/bash
# ==========================================
# PDF Contract Pipeline - Shared Configuration
# Source this file before running other scripts
# ==========================================

# ==========================================
# Configuration - EDIT THESE VALUES
# ==========================================
export PROJECT_NAME="contract-pipeline"
export AWS_REGION="us-east-1"
export ENVIRONMENT="dev"

# Redshift credentials (CHANGE THESE!)
export REDSHIFT_ADMIN_USER="admin"
export REDSHIFT_ADMIN_PASSWORD="${REDSHIFT_ADMIN_PASSWORD:-CHANGE_ME_BEFORE_RUNNING}"  # Set this via environment variable!
export REDSHIFT_DATABASE="contracts_dw"

# ==========================================
# Derived names (auto-generated)
# ==========================================
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export S3_RAW_BUCKET="${PROJECT_NAME}-raw-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
export S3_PROCESSED_BUCKET="${PROJECT_NAME}-processed-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
export ECR_REPO_NAME="${PROJECT_NAME}-extractor"
export ECS_CLUSTER_NAME="${PROJECT_NAME}-cluster-${ENVIRONMENT}"
export ECS_SERVICE_NAME="${PROJECT_NAME}-extractor-service"
export ECS_TASK_FAMILY="${PROJECT_NAME}-extractor-task"
export SQS_QUEUE_NAME="${PROJECT_NAME}-extraction-trigger-${ENVIRONMENT}"
export REDSHIFT_NAMESPACE="${PROJECT_NAME}-${ENVIRONMENT}"
export REDSHIFT_WORKGROUP="${PROJECT_NAME}-workgroup-${ENVIRONMENT}"
export IAM_ROLE_NAME="${PROJECT_NAME}-ecs-task-role-${ENVIRONMENT}"
export IAM_EXECUTION_ROLE_NAME="${PROJECT_NAME}-ecs-execution-role-${ENVIRONMENT}"
export LOG_GROUP_NAME="/ecs/${PROJECT_NAME}-${ENVIRONMENT}"
export REDSHIFT_SG_NAME="${PROJECT_NAME}-redshift-sg"

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m' # No Color

echo -e "${GREEN}Configuration Loaded${NC}"
echo "  Project:     ${PROJECT_NAME}"
echo "  Region:      ${AWS_REGION}"
echo "  Environment: ${ENVIRONMENT}"
echo "  Account ID:  ${AWS_ACCOUNT_ID}"
echo ""
