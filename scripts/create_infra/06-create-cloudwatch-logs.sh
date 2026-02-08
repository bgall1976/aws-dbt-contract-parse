#!/bin/bash
# ==========================================
# Step 6: Create CloudWatch Log Group
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

LOG_GROUP_NAME="/ecs/${PROJECT_NAME}-${ENVIRONMENT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 6: Creating CloudWatch Log Group...${NC}"
echo "  Region: $AWS_REGION"
echo "  Log Group: $LOG_GROUP_NAME"

# Check if log group exists
LOG_EXISTS=$(aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP_NAME" \
    --region "$AWS_REGION" \
    --query "logGroups[?logGroupName=='$LOG_GROUP_NAME'].logGroupName" \
    --output text 2>/dev/null)

if [ -n "$LOG_EXISTS" ] && [ "$LOG_EXISTS" != "None" ]; then
    echo -e "  ${GREEN}[OK] Log group already exists${NC}"
else
    echo "  Creating log group..."
    aws logs create-log-group \
        --log-group-name "$LOG_GROUP_NAME" \
        --region "$AWS_REGION" 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}[OK] Created log group${NC}"
        
        # Set retention policy (30 days)
        aws logs put-retention-policy \
            --log-group-name "$LOG_GROUP_NAME" \
            --retention-in-days 30 \
            --region "$AWS_REGION" 2>/dev/null
        echo "  Retention policy set to 30 days"
    else
        echo -e "  ${RED}[FAILED] Could not create log group${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Step 6 Complete: CloudWatch Log Group Created${NC}"
