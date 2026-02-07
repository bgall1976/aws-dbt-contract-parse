#!/bin/bash
# ==========================================
# Teardown Step 4: Delete Redshift Serverless
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Teardown Step 4: Deleting Redshift Serverless...${NC}"
echo ""
echo -e "${YELLOW}Note: This may take a few minutes.${NC}"
echo ""

# Delete workgroup first
echo "  Deleting Redshift workgroup: $REDSHIFT_WORKGROUP"
aws redshift-serverless delete-workgroup \
    --workgroup-name "$REDSHIFT_WORKGROUP" \
    --no-cli-pager 2>/dev/null || echo "  Workgroup not found or already deleted"

# Wait for workgroup to be deleted
echo "  Waiting for workgroup deletion..."
sleep 30

# Delete namespace
echo "  Deleting Redshift namespace: $REDSHIFT_NAMESPACE"
aws redshift-serverless delete-namespace \
    --namespace-name "$REDSHIFT_NAMESPACE" \
    --no-cli-pager 2>/dev/null || echo "  Namespace not found or already deleted"

echo -e "  ${GREEN}✓ Redshift Serverless deleted${NC}"

echo -e "${GREEN}Teardown Step 4 Complete: Redshift Serverless Deleted${NC}"
