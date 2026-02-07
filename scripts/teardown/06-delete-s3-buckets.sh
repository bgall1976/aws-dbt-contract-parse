#!/bin/bash
# ==========================================
# Teardown Step 6: Delete S3 Buckets
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Teardown Step 6: Deleting S3 Buckets...${NC}"

# Function to empty and delete bucket
delete_bucket() {
    local BUCKET=$1
    
    if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
        echo "  Emptying bucket: $BUCKET"
        
        # Delete all objects
        aws s3 rm "s3://$BUCKET" --recursive 2>/dev/null || true
        
        # Delete all object versions (for versioned buckets)
        echo "  Deleting object versions..."
        aws s3api list-object-versions --bucket "$BUCKET" \
            --query 'Versions[*].{Key:Key,VersionId:VersionId}' \
            --output json 2>/dev/null | \
        jq -r '.[] | "\(.Key) \(.VersionId)"' 2>/dev/null | \
        while read KEY VERSION; do
            if [ -n "$KEY" ] && [ -n "$VERSION" ]; then
                aws s3api delete-object \
                    --bucket "$BUCKET" \
                    --key "$KEY" \
                    --version-id "$VERSION" 2>/dev/null || true
            fi
        done
        
        # Delete all delete markers
        echo "  Deleting delete markers..."
        aws s3api list-object-versions --bucket "$BUCKET" \
            --query 'DeleteMarkers[*].{Key:Key,VersionId:VersionId}' \
            --output json 2>/dev/null | \
        jq -r '.[] | "\(.Key) \(.VersionId)"' 2>/dev/null | \
        while read KEY VERSION; do
            if [ -n "$KEY" ] && [ -n "$VERSION" ]; then
                aws s3api delete-object \
                    --bucket "$BUCKET" \
                    --key "$KEY" \
                    --version-id "$VERSION" 2>/dev/null || true
            fi
        done
        
        # Delete the bucket
        echo "  Deleting bucket: $BUCKET"
        aws s3api delete-bucket --bucket "$BUCKET" 2>/dev/null || true
        
        echo -e "  ${GREEN}✓ Deleted $BUCKET${NC}"
    else
        echo "  Bucket $BUCKET not found, skipping..."
    fi
}

delete_bucket "$S3_RAW_BUCKET"
delete_bucket "$S3_PROCESSED_BUCKET"

echo -e "${GREEN}Teardown Step 6 Complete: S3 Buckets Deleted${NC}"
