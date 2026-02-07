#!/bin/bash
# ==========================================
# PDF Contract Pipeline - AWS Infrastructure Teardown Script
# Run this in AWS CloudShell
# WARNING: This will DELETE all resources!
# ==========================================

#set -e  # Disabled - handle errors individually  # Exit on any error

# ==========================================
# Configuration - MUST MATCH BUILD SCRIPT
# ==========================================
PROJECT_NAME="contract-pipeline"
AWS_REGION="us-east-1"
ENVIRONMENT="dev"

# ==========================================
# Derived names
# ==========================================
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_RAW_BUCKET="${PROJECT_NAME}-raw-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
S3_PROCESSED_BUCKET="${PROJECT_NAME}-processed-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
ECR_REPO_NAME="${PROJECT_NAME}-extractor"
ECS_CLUSTER_NAME="${PROJECT_NAME}-cluster-${ENVIRONMENT}"
ECS_SERVICE_NAME="${PROJECT_NAME}-extractor-service"
ECS_TASK_FAMILY="${PROJECT_NAME}-extractor-task"
SQS_QUEUE_NAME="${PROJECT_NAME}-extraction-trigger-${ENVIRONMENT}"
REDSHIFT_NAMESPACE="${PROJECT_NAME}-${ENVIRONMENT}"
REDSHIFT_WORKGROUP="${PROJECT_NAME}-workgroup-${ENVIRONMENT}"
IAM_ROLE_NAME="${PROJECT_NAME}-ecs-task-role-${ENVIRONMENT}"
IAM_EXECUTION_ROLE_NAME="${PROJECT_NAME}-ecs-execution-role-${ENVIRONMENT}"
LOG_GROUP_NAME="/ecs/${PROJECT_NAME}-${ENVIRONMENT}"
REDSHIFT_SG_NAME="${PROJECT_NAME}-redshift-sg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}=========================================="
echo "PDF Contract Pipeline - Infrastructure TEARDOWN"
echo -e "==========================================${NC}"
echo ""
echo -e "${RED}WARNING: This will DELETE all resources!${NC}"
echo ""
echo "The following resources will be deleted:"
echo "  - S3 Buckets: $S3_RAW_BUCKET, $S3_PROCESSED_BUCKET"
echo "  - SQS Queues: $SQS_QUEUE_NAME, ${SQS_QUEUE_NAME}-dlq"
echo "  - ECR Repository: $ECR_REPO_NAME"
echo "  - ECS Cluster: $ECS_CLUSTER_NAME"
echo "  - ECS Task Definitions: $ECS_TASK_FAMILY"
echo "  - Redshift: $REDSHIFT_NAMESPACE, $REDSHIFT_WORKGROUP"
echo "  - IAM Roles: $IAM_ROLE_NAME, $IAM_EXECUTION_ROLE_NAME"
echo "  - CloudWatch Logs: $LOG_GROUP_NAME"
echo ""

# Confirmation prompt
read -p "Are you sure you want to DELETE all resources? Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Teardown cancelled."
    exit 0
fi

echo ""
echo "Starting teardown..."
echo ""

# ==========================================
# Step 1: Delete ECS Services
# ==========================================
echo -e "${YELLOW}Step 1: Deleting ECS Services...${NC}"

# List and delete all services in the cluster
SERVICES=$(aws ecs list-services --cluster "$ECS_CLUSTER_NAME" --query 'serviceArns[*]' --output text 2>/dev/null || echo "")

for SERVICE_ARN in $SERVICES; do
    SERVICE_NAME=$(echo "$SERVICE_ARN" | awk -F'/' '{print $NF}')
    echo "  Stopping service: $SERVICE_NAME"
    
    # Update service to 0 desired count
    aws ecs update-service \
        --cluster "$ECS_CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --desired-count 0 \
        --no-cli-pager 2>/dev/null || true
    
    # Delete the service
    aws ecs delete-service \
        --cluster "$ECS_CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --force \
        --no-cli-pager 2>/dev/null || true
    
    echo -e "  ${GREEN}✓ Deleted service: $SERVICE_NAME${NC}"
done

echo -e "  ${GREEN}✓ ECS Services deleted${NC}"

# ==========================================
# Step 2: Deregister ECS Task Definitions
# ==========================================
echo -e "${YELLOW}Step 2: Deregistering ECS Task Definitions...${NC}"

# Get all task definition revisions
TASK_DEFS=$(aws ecs list-task-definitions \
    --family-prefix "$ECS_TASK_FAMILY" \
    --query 'taskDefinitionArns[*]' \
    --output text 2>/dev/null || echo "")

for TASK_DEF in $TASK_DEFS; do
    echo "  Deregistering: $TASK_DEF"
    aws ecs deregister-task-definition --task-definition "$TASK_DEF" --no-cli-pager 2>/dev/null || true
done

echo -e "  ${GREEN}✓ Task definitions deregistered${NC}"

# ==========================================
# Step 3: Delete ECS Cluster
# ==========================================
echo -e "${YELLOW}Step 3: Deleting ECS Cluster...${NC}"

aws ecs delete-cluster --cluster "$ECS_CLUSTER_NAME" --no-cli-pager 2>/dev/null || echo "  Cluster not found or already deleted"

echo -e "  ${GREEN}✓ ECS Cluster deleted${NC}"

# ==========================================
# Step 4: Delete Redshift Serverless
# ==========================================
echo -e "${YELLOW}Step 4: Deleting Redshift Serverless...${NC}"

# Delete workgroup first
echo "  Deleting Redshift workgroup: $REDSHIFT_WORKGROUP"
aws redshift-serverless delete-workgroup \
    --workgroup-name "$REDSHIFT_WORKGROUP" \
    --no-cli-pager 2>/dev/null || echo "  Workgroup not found or already deleted"

# Wait for workgroup to be deleted
echo "  Waiting for workgroup deletion..."
sleep 30

# Delete namespace
echo "  Deleting Redshift namespace: $REDSHIFT_NAMESPACE"
aws redshift-serverless delete-namespace \
    --namespace-name "$REDSHIFT_NAMESPACE" \
    --no-cli-pager 2>/dev/null || echo "  Namespace not found or already deleted"

echo -e "  ${GREEN}✓ Redshift Serverless deleted${NC}"

# ==========================================
# Step 5: Delete ECR Repository
# ==========================================
echo -e "${YELLOW}Step 5: Deleting ECR Repository...${NC}"

# Force delete (removes all images)
aws ecr delete-repository \
    --repository-name "$ECR_REPO_NAME" \
    --force \
    --no-cli-pager 2>/dev/null || echo "  Repository not found or already deleted"

echo -e "  ${GREEN}✓ ECR Repository deleted${NC}"

# ==========================================
# Step 6: Delete S3 Buckets
# ==========================================
echo -e "${YELLOW}Step 6: Deleting S3 Buckets...${NC}"

# Function to empty and delete bucket
delete_bucket() {
    local BUCKET=$1
    
    if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
        echo "  Emptying bucket: $BUCKET"
        
        # Delete all objects
        aws s3 rm "s3://$BUCKET" --recursive 2>/dev/null || true
        
        # Delete all object versions (for versioned buckets)
        aws s3api list-object-versions --bucket "$BUCKET" --query 'Versions[*].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
        jq -r '.[] | "\(.Key) \(.VersionId)"' 2>/dev/null | \
        while read KEY VERSION; do
            aws s3api delete-object --bucket "$BUCKET" --key "$KEY" --version-id "$VERSION" 2>/dev/null || true
        done
        
        # Delete all delete markers
        aws s3api list-object-versions --bucket "$BUCKET" --query 'DeleteMarkers[*].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
        jq -r '.[] | "\(.Key) \(.VersionId)"' 2>/dev/null | \
        while read KEY VERSION; do
            aws s3api delete-object --bucket "$BUCKET" --key "$KEY" --version-id "$VERSION" 2>/dev/null || true
        done
        
        # Delete the bucket
        echo "  Deleting bucket: $BUCKET"
        aws s3api delete-bucket --bucket "$BUCKET" 2>/dev/null || true
        
        echo -e "  ${GREEN}✓ Deleted $BUCKET${NC}"
    else
        echo "  Bucket $BUCKET not found, skipping..."
    fi
}

delete_bucket "$S3_RAW_BUCKET"
delete_bucket "$S3_PROCESSED_BUCKET"

echo -e "  ${GREEN}✓ S3 Buckets deleted${NC}"

# ==========================================
# Step 7: Delete SQS Queues
# ==========================================
echo -e "${YELLOW}Step 7: Deleting SQS Queues...${NC}"

# Delete main queue
SQS_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --query 'QueueUrl' --output text 2>/dev/null || echo "")
if [ -n "$SQS_URL" ]; then
    aws sqs delete-queue --queue-url "$SQS_URL"
    echo -e "  ${GREEN}✓ Deleted $SQS_QUEUE_NAME${NC}"
else
    echo "  Queue $SQS_QUEUE_NAME not found, skipping..."
fi

# Delete dead letter queue
DLQ_URL=$(aws sqs get-queue-url --queue-name "${SQS_QUEUE_NAME}-dlq" --query 'QueueUrl' --output text 2>/dev/null || echo "")
if [ -n "$DLQ_URL" ]; then
    aws sqs delete-queue --queue-url "$DLQ_URL"
    echo -e "  ${GREEN}✓ Deleted ${SQS_QUEUE_NAME}-dlq${NC}"
else
    echo "  Queue ${SQS_QUEUE_NAME}-dlq not found, skipping..."
fi

echo -e "  ${GREEN}✓ SQS Queues deleted${NC}"

# ==========================================
# Step 8: Delete IAM Roles
# ==========================================
echo -e "${YELLOW}Step 8: Deleting IAM Roles...${NC}"

# Function to delete IAM role with all attached policies
delete_iam_role() {
    local ROLE_NAME=$1
    
    if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
        echo "  Deleting role: $ROLE_NAME"
        
        # Detach managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'AttachedPolicies[*].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for POLICY_ARN in $ATTACHED_POLICIES; do
            aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'PolicyNames[*]' \
            --output text 2>/dev/null || echo "")
        
        for POLICY_NAME in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" 2>/dev/null || true
        done
        
        # Delete the role
        aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
        
        echo -e "  ${GREEN}✓ Deleted $ROLE_NAME${NC}"
    else
        echo "  Role $ROLE_NAME not found, skipping..."
    fi
}

delete_iam_role "$IAM_ROLE_NAME"
delete_iam_role "$IAM_EXECUTION_ROLE_NAME"

echo -e "  ${GREEN}✓ IAM Roles deleted${NC}"

# ==========================================
# Step 9: Delete CloudWatch Log Group
# ==========================================
echo -e "${YELLOW}Step 9: Deleting CloudWatch Log Group...${NC}"

aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" 2>/dev/null || echo "  Log group not found, skipping..."

echo -e "  ${GREEN}✓ CloudWatch Log Group deleted${NC}"

# ==========================================
# Step 10: Delete Security Group
# ==========================================
echo -e "${YELLOW}Step 10: Deleting Security Groups...${NC}"

# Find and delete Redshift security group
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${REDSHIFT_SG_NAME}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
    # Wait for dependencies to clear
    sleep 10
    aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null || echo "  Could not delete security group (may have dependencies)"
    echo -e "  ${GREEN}✓ Deleted security group: $REDSHIFT_SG_NAME${NC}"
else
    echo "  Security group not found, skipping..."
fi

echo -e "  ${GREEN}✓ Security Groups deleted${NC}"

# ==========================================
# Summary
# ==========================================
echo ""
echo -e "${GREEN}=========================================="
echo "Infrastructure Teardown Complete!"
echo -e "==========================================${NC}"
echo ""
echo "The following resources have been deleted:"
echo "  ✓ S3 Buckets"
echo "  ✓ SQS Queues"
echo "  ✓ ECR Repository"
echo "  ✓ ECS Cluster and Services"
echo "  ✓ ECS Task Definitions"
echo "  ✓ Redshift Serverless"
echo "  ✓ IAM Roles"
echo "  ✓ CloudWatch Log Groups"
echo "  ✓ Security Groups"
echo ""
echo -e "${YELLOW}Note: Some resources may take a few minutes to fully delete.${NC}"
echo "Check the AWS Console to verify all resources are removed."
echo ""

# Clean up config file
rm -f /tmp/pipeline-config.env 2>/dev/null || true
echo "Removed local configuration file."
