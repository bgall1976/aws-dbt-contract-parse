#!/bin/bash
# ==========================================
# Teardown Step 9: Delete CloudWatch Log Group
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Teardown Step 9: Deleting CloudWatch Log Group...${NC}"

aws logs delete-log-group \
    --log-group-name "$LOG_GROUP_NAME" \
    2>/dev/null || echo "  Log group not found, skipping..."

echo -e "  ${GREEN}✓ CloudWatch Log Group deleted${NC}"

echo -e "${GREEN}Teardown Step 9 Complete: CloudWatch Log Group Deleted${NC}"
