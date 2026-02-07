#!/bin/bash
# ==========================================
# Teardown Step 2: Deregister ECS Task Definitions
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Teardown Step 2: Deregistering ECS Task Definitions...${NC}"

# Get all task definition revisions
TASK_DEFS=$(aws ecs list-task-definitions \
    --family-prefix "$ECS_TASK_FAMILY" \
    --query 'taskDefinitionArns[*]' \
    --output text 2>/dev/null || echo "")

if [ -z "$TASK_DEFS" ]; then
    echo "  No task definitions found, skipping..."
else
    for TASK_DEF in $TASK_DEFS; do
        echo "  Deregistering: $TASK_DEF"
        aws ecs deregister-task-definition \
            --task-definition "$TASK_DEF" \
            --no-cli-pager 2>/dev/null || true
    done
    echo -e "  ${GREEN}✓ Task definitions deregistered${NC}"
fi

echo -e "${GREEN}Teardown Step 2 Complete: ECS Task Definitions Deregistered${NC}"
