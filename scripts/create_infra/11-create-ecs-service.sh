#!/bin/bash
# ==========================================
# Step 11: Create ECS Service
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

ECS_CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"
ECS_SERVICE_NAME="contract-extractor"
ECS_TASK_FAMILY="${PROJECT_NAME}-task"
SECURITY_GROUP_NAME="${PROJECT_NAME}-redshift-sg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 11: Creating ECS Service...${NC}"
echo "  Region: $AWS_REGION"
echo "  Cluster: $ECS_CLUSTER_NAME"
echo "  Service: $ECS_SERVICE_NAME"
echo "  Task Family: $ECS_TASK_FAMILY"

# ==========================================
# Verify prerequisites
# ==========================================
echo ""
echo "Verifying prerequisites..."

# Check if cluster exists
CLUSTER_STATUS=$(aws ecs describe-clusters \
    --clusters "$ECS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'clusters[0].status' \
    --output text 2>/dev/null)

if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    echo -e "  ${RED}[FAILED] ECS cluster not found or not active: $ECS_CLUSTER_NAME${NC}"
    echo "  Please run 07-create-ecs-cluster.sh first"
else
echo -e "  ${GREEN}[OK] ECS cluster exists${NC}"

# Check if task definition exists
TASK_DEF_EXISTS=$(aws ecs list-task-definitions \
    --family-prefix "$ECS_TASK_FAMILY" \
    --region "$AWS_REGION" \
    --query 'taskDefinitionArns[0]' \
    --output text 2>/dev/null)

if [ -z "$TASK_DEF_EXISTS" ] || [ "$TASK_DEF_EXISTS" == "None" ]; then
    echo -e "  ${RED}[FAILED] Task definition not found: $ECS_TASK_FAMILY${NC}"
    echo "  Please run 08-create-ecs-task-definition.sh first"
else
echo -e "  ${GREEN}[OK] Task definition exists${NC}"

# ==========================================
# Get networking configuration
# ==========================================
echo ""
echo "Getting network configuration..."

DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --region "$AWS_REGION" \
    --output text 2>/dev/null)

echo "  VPC: $DEFAULT_VPC_ID"

SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
    --query 'Subnets[0].SubnetId' \
    --region "$AWS_REGION" \
    --output text 2>/dev/null)

echo "  Subnet: $SUBNET_ID"

# Get security group (try project-specific first, then default)
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --region "$AWS_REGION" \
    --output text 2>/dev/null)

if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    echo "  Project security group not found, using default..."
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" "Name=group-name,Values=default" \
        --query 'SecurityGroups[0].GroupId' \
        --region "$AWS_REGION" \
        --output text 2>/dev/null)
fi

echo "  Security Group: $SG_ID"

# ==========================================
# Check if service already exists
# ==========================================
echo ""
echo "Checking if service already exists..."

SERVICE_STATUS=$(aws ecs describe-services \
    --cluster "$ECS_CLUSTER_NAME" \
    --services "$ECS_SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].status' \
    --output text 2>/dev/null)

if [ "$SERVICE_STATUS" == "ACTIVE" ]; then
    echo -e "  ${GREEN}[OK] Service already exists and is active${NC}"
    echo ""
    echo "To force a new deployment, run:"
    echo "  aws ecs update-service --cluster $ECS_CLUSTER_NAME --service $ECS_SERVICE_NAME --force-new-deployment --region $AWS_REGION"
else

# ==========================================
# Create ECS Service
# ==========================================
echo ""
echo "Creating ECS service..."

CREATE_RESULT=$(aws ecs create-service \
    --cluster "$ECS_CLUSTER_NAME" \
    --service-name "$ECS_SERVICE_NAME" \
    --task-definition "$ECS_TASK_FAMILY" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
    --region "$AWS_REGION" \
    --query 'service.serviceArn' \
    --output text 2>&1)

if [ $? -eq 0 ] && [ -n "$CREATE_RESULT" ] && [ "$CREATE_RESULT" != "None" ]; then
    echo -e "  ${GREEN}[OK] Created ECS service${NC}"
    echo "  Service ARN: $CREATE_RESULT"
else
    echo -e "  ${RED}[FAILED] Could not create ECS service${NC}"
    echo "  Error: $CREATE_RESULT"
fi

fi  # End service exists check

fi  # End task definition check
fi  # End cluster check

# ==========================================
# Summary
# ==========================================
echo ""
echo "=========================================="
echo "ECS Service Summary"
echo "=========================================="
echo "  Cluster: $ECS_CLUSTER_NAME"
echo "  Service: $ECS_SERVICE_NAME"
echo "  Task Definition: $ECS_TASK_FAMILY"
echo "  Desired Count: 1"
echo "  Launch Type: FARGATE"
echo ""
echo "To check service status:"
echo "  aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION --query 'services[0].status'"
echo ""
echo "To view running tasks:"
echo "  aws ecs list-tasks --cluster $ECS_CLUSTER_NAME --service-name $ECS_SERVICE_NAME --region $AWS_REGION"
echo ""
echo "To view logs:"
echo "  aws logs tail /ecs/${PROJECT_NAME}-${ENVIRONMENT} --follow --region $AWS_REGION"
echo ""
echo -e "${GREEN}Step 11 Complete: ECS Service Created${NC}"
