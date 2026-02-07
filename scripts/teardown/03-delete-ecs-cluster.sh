#!/bin/bash
# ==========================================
# Teardown Step 3: Delete ECS Cluster
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Teardown Step 3: Deleting ECS Cluster...${NC}"

aws ecs delete-cluster \
    --cluster "$ECS_CLUSTER_NAME" \
    --no-cli-pager 2>/dev/null || echo "  Cluster not found or already deleted"

echo -e "  ${GREEN}✓ ECS Cluster deleted${NC}"

echo -e "${GREEN}Teardown Step 3 Complete: ECS Cluster Deleted${NC}"
