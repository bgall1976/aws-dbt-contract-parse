#!/bin/bash
# ==========================================
# Step 7: Create ECS Cluster
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

ECS_CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 7: Creating ECS Cluster...${NC}"
echo "  Region: $AWS_REGION"
echo "  Cluster Name: $ECS_CLUSTER_NAME"

# Check if cluster exists
CLUSTER_STATUS=$(aws ecs describe-clusters \
    --clusters "$ECS_CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'clusters[0].status' \
    --output text 2>/dev/null)

if [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo -e "  ${GREEN}[OK] Cluster already exists and is active${NC}"
else
    echo "  Creating cluster..."
    CREATE_RESULT=$(aws ecs create-cluster \
        --cluster-name "$ECS_CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'cluster.clusterArn' \
        --output text 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$CREATE_RESULT" ] && [ "$CREATE_RESULT" != "None" ]; then
        echo -e "  ${GREEN}[OK] Created ECS cluster${NC}"
        echo "  Cluster ARN: $CREATE_RESULT"
    else
        echo -e "  ${RED}[FAILED] Could not create cluster${NC}"
        echo "  Error: $CREATE_RESULT"
    fi
fi

echo ""
echo -e "${GREEN}Step 7 Complete: ECS Cluster Created${NC}"
