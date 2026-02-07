#!/bin/bash
# ==========================================
# Step 7: Create ECS Cluster
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Step 7: Creating ECS Cluster...${NC}"

# Check if cluster exists
cluster_exists() {
    aws ecs describe-clusters --clusters "$1" \
        --query "clusters[?status=='ACTIVE'].clusterName" \
        --output text 2>/dev/null | grep -q "$1" && return 0 || return 1
}

if cluster_exists "$ECS_CLUSTER_NAME"; then
    echo "  ECS cluster $ECS_CLUSTER_NAME already exists, skipping..."
else
    echo "  Creating ECS cluster: $ECS_CLUSTER_NAME"
    
    aws ecs create-cluster \
        --cluster-name "$ECS_CLUSTER_NAME" \
        --capacity-providers FARGATE FARGATE_SPOT \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1
    
    echo -e "  ${GREEN}✓ Created ECS cluster${NC}"
fi

echo "  Cluster Name: $ECS_CLUSTER_NAME"
echo "  Capacity Providers: FARGATE, FARGATE_SPOT"

echo -e "${GREEN}Step 7 Complete: ECS Cluster Created${NC}"
