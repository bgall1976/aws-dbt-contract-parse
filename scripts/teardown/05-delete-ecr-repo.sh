#!/bin/bash
# ==========================================
# Teardown Step 5: Delete ECR Repository
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Teardown Step 5: Deleting ECR Repository...${NC}"

# Force delete (removes all images)
aws ecr delete-repository \
    --repository-name "$ECR_REPO_NAME" \
    --force \
    --no-cli-pager 2>/dev/null || echo "  Repository not found or already deleted"

echo -e "  ${GREEN}✓ ECR Repository deleted${NC}"

echo -e "${GREEN}Teardown Step 5 Complete: ECR Repository Deleted${NC}"
