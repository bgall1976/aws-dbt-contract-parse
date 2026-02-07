#!/bin/bash
# ==========================================
# Step 6: Create CloudWatch Log Group
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Step 6: Creating CloudWatch Log Group...${NC}"

# Create log group (ignore error if exists)
aws logs create-log-group \
    --log-group-name "$LOG_GROUP_NAME" \
    2>/dev/null || echo "  Log group already exists, skipping creation..."

# Set retention policy
aws logs put-retention-policy \
    --log-group-name "$LOG_GROUP_NAME" \
    --retention-in-days 30

echo -e "  ${GREEN}✓ CloudWatch Log Group configured${NC}"
echo "  Log Group: $LOG_GROUP_NAME"
echo "  Retention: 30 days"

echo -e "${GREEN}Step 6 Complete: CloudWatch Log Group Created${NC}"
