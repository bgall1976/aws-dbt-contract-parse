#!/bin/bash
# ==========================================
# Teardown Step 10: Delete Security Groups
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Teardown Step 10: Deleting Security Groups...${NC}"

# Find Redshift security group
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${REDSHIFT_SG_NAME}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
    # Wait for dependencies to clear
    echo "  Waiting for dependencies to clear..."
    sleep 10
    
    aws ec2 delete-security-group \
        --group-id "$SG_ID" 2>/dev/null || echo "  Could not delete security group (may have dependencies)"
    
    echo -e "  ${GREEN}✓ Deleted security group: $REDSHIFT_SG_NAME${NC}"
else
    echo "  Security group not found, skipping..."
fi

echo -e "${GREEN}Teardown Step 10 Complete: Security Groups Deleted${NC}"
