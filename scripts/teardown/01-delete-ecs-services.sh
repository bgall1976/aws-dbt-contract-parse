#!/bin/bash
# ==========================================
# Teardown Step 1: Delete ECS Services
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Teardown Step 1: Deleting ECS Services...${NC}"

# List all services in the cluster
SERVICES=$(aws ecs list-services \
    --cluster "$ECS_CLUSTER_NAME" \
    --query 'serviceArns[*]' \
    --output text 2>/dev/null || echo "")

if [ -z "$SERVICES" ]; then
    echo "  No ECS services found, skipping..."
else
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
fi

echo -e "${GREEN}Teardown Step 1 Complete: ECS Services Deleted${NC}"
