#!/bin/bash
# ==========================================
# Teardown Step 8: Delete IAM Roles
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Teardown Step 8: Deleting IAM Roles...${NC}"

# Function to delete IAM role with all attached policies
delete_iam_role() {
    local ROLE_NAME=$1
    
    if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
        echo "  Deleting role: $ROLE_NAME"
        
        # Detach managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'AttachedPolicies[*].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for POLICY_ARN in $ATTACHED_POLICIES; do
            if [ -n "$POLICY_ARN" ]; then
                echo "    Detaching policy: $POLICY_ARN"
                aws iam detach-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-arn "$POLICY_ARN" 2>/dev/null || true
            fi
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'PolicyNames[*]' \
            --output text 2>/dev/null || echo "")
        
        for POLICY_NAME in $INLINE_POLICIES; do
            if [ -n "$POLICY_NAME" ]; then
                echo "    Deleting inline policy: $POLICY_NAME"
                aws iam delete-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-name "$POLICY_NAME" 2>/dev/null || true
            fi
        done
        
        # Delete the role
        aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
        
        echo -e "  ${GREEN}✓ Deleted $ROLE_NAME${NC}"
    else
        echo "  Role $ROLE_NAME not found, skipping..."
    fi
}

delete_iam_role "$IAM_ROLE_NAME"
delete_iam_role "$IAM_EXECUTION_ROLE_NAME"

echo -e "${GREEN}Teardown Step 8 Complete: IAM Roles Deleted${NC}"
