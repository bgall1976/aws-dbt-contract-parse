#!/bin/bash
# ==========================================
# Step 9: Create Redshift Serverless
# ==========================================

# ==========================================
# Configuration - Set these variables
# ==========================================
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REDSHIFT_ADMIN_USER="${REDSHIFT_ADMIN_USER:-admin}"
REDSHIFT_ADMIN_PASSWORD="${REDSHIFT_ADMIN_PASSWORD:-}"
REDSHIFT_DATABASE="${REDSHIFT_DATABASE:-contracts_dw}"

# Derived names
REDSHIFT_NAMESPACE="${PROJECT_NAME}-${ENVIRONMENT}"
REDSHIFT_WORKGROUP="${PROJECT_NAME}-workgroup-${ENVIRONMENT}"
REDSHIFT_SG_NAME="${PROJECT_NAME}-redshift-sg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 9: Creating Redshift Serverless...${NC}"
echo ""
echo "  Namespace:  $REDSHIFT_NAMESPACE"
echo "  Workgroup:  $REDSHIFT_WORKGROUP"
echo ""

# ==========================================
# Validate Password
# ==========================================
if [ -z "$REDSHIFT_ADMIN_PASSWORD" ] || [ "$REDSHIFT_ADMIN_PASSWORD" = "CHANGE_ME_BEFORE_RUNNING" ]; then
    echo -e "${RED}ERROR: REDSHIFT_ADMIN_PASSWORD is not set!${NC}"
    echo ""
    echo "Please set the password before running this script:"
    echo "  export REDSHIFT_ADMIN_PASSWORD='YourSecurePassword123!'"
    echo ""
    echo "Password requirements:"
    echo "  - At least 8 characters"
    echo "  - At least one uppercase letter"
    echo "  - At least one lowercase letter"
    echo "  - At least one number"
    echo ""
    echo -e "${RED}Script stopped. Set the password and try again.${NC}"
else

echo -e "${GREEN}Password is set.${NC}"
echo -e "${YELLOW}WARNING: This step can take 5-10 minutes to complete.${NC}"
echo ""

# ==========================================
# Create Namespace
# ==========================================
echo "Checking if namespace exists..."
NAMESPACE_EXISTS=$(aws redshift-serverless list-namespaces \
    --query "namespaces[?namespaceName=='${REDSHIFT_NAMESPACE}'].namespaceName" \
    --output text 2>/dev/null || echo "")

if [ -n "$NAMESPACE_EXISTS" ]; then
    echo "  Redshift namespace $REDSHIFT_NAMESPACE already exists, skipping..."
else
    echo "  Creating Redshift Serverless namespace: $REDSHIFT_NAMESPACE"
    
    if aws redshift-serverless create-namespace \
        --namespace-name "$REDSHIFT_NAMESPACE" \
        --admin-username "$REDSHIFT_ADMIN_USER" \
        --admin-user-password "$REDSHIFT_ADMIN_PASSWORD" \
        --db-name "$REDSHIFT_DATABASE" \
        --tags key=Project,value="$PROJECT_NAME" key=Environment,value="$ENVIRONMENT" \
        --output text > /dev/null 2>&1; then
        echo -e "  ${GREEN}[OK] Created Redshift namespace${NC}"
    else
        echo -e "  ${RED}[FAILED] Failed to create namespace${NC}"
    fi
    
    # Wait for namespace to be available
    echo "  Waiting for namespace to be available..."
    for i in {1..30}; do
        STATUS=$(aws redshift-serverless get-namespace \
            --namespace-name "$REDSHIFT_NAMESPACE" \
            --query "namespace.status" --output text 2>/dev/null || echo "NOTFOUND")
        if [ "$STATUS" = "AVAILABLE" ]; then
            echo -e "  ${GREEN}[OK] Namespace is available${NC}"
            break
        fi
        echo "    Status: $STATUS (waiting 10s, attempt $i/30)"
        sleep 10
    done
fi

# ==========================================
# Create Workgroup
# ==========================================
echo ""
echo "Checking if workgroup exists..."
WORKGROUP_EXISTS=$(aws redshift-serverless list-workgroups \
    --query "workgroups[?workgroupName=='${REDSHIFT_WORKGROUP}'].workgroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$WORKGROUP_EXISTS" ]; then
    echo "  Redshift workgroup $REDSHIFT_WORKGROUP already exists, skipping..."
else
    echo "  Creating Redshift Serverless workgroup: $REDSHIFT_WORKGROUP"
    
    # Get default VPC and subnets
    DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    echo "  Using VPC: $DEFAULT_VPC_ID"
    
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
        --query 'Subnets[*].SubnetId' --output text)
    
    echo "  Subnets: $SUBNET_IDS"
    
    # Create or find security group for Redshift
    echo "  Creating/finding security group..."
    REDSHIFT_SG_ID=$(aws ec2 create-security-group \
        --group-name "${REDSHIFT_SG_NAME}" \
        --description "Security group for Redshift Serverless" \
        --vpc-id "$DEFAULT_VPC_ID" \
        --query 'GroupId' --output text 2>/dev/null)
    
    if [ -z "$REDSHIFT_SG_ID" ] || [ "$REDSHIFT_SG_ID" = "None" ]; then
        REDSHIFT_SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=${REDSHIFT_SG_NAME}" \
            --query 'SecurityGroups[0].GroupId' --output text)
    fi
    
    echo "  Security Group: $REDSHIFT_SG_ID"
    
    # Allow inbound on port 5439
    aws ec2 authorize-security-group-ingress \
        --group-id "$REDSHIFT_SG_ID" \
        --protocol tcp \
        --port 5439 \
        --cidr "0.0.0.0/0" > /dev/null 2>&1 || echo "  (Ingress rule already exists)"
    
    # Create workgroup
    echo "  Creating workgroup..."
    if aws redshift-serverless create-workgroup \
        --workgroup-name "$REDSHIFT_WORKGROUP" \
        --namespace-name "$REDSHIFT_NAMESPACE" \
        --base-capacity 8 \
        --security-group-ids "$REDSHIFT_SG_ID" \
        --subnet-ids $SUBNET_IDS \
        --publicly-accessible \
        --tags key=Project,value="$PROJECT_NAME" key=Environment,value="$ENVIRONMENT" \
        --output text > /dev/null 2>&1; then
        echo -e "  ${GREEN}[OK] Workgroup creation started${NC}"
    else
        echo -e "  ${RED}[FAILED] Failed to create workgroup${NC}"
    fi
    
    # Wait for workgroup to be available (custom wait loop since 'wait' command doesn't exist)
    echo ""
    echo "  Waiting for workgroup to become available..."
    echo "  (This typically takes 5-10 minutes)"
    echo ""
    for i in {1..60}; do
        STATUS=$(aws redshift-serverless get-workgroup \
            --workgroup-name "$REDSHIFT_WORKGROUP" \
            --query "workgroup.status" --output text 2>/dev/null || echo "NOTFOUND")
        
        if [ "$STATUS" = "AVAILABLE" ]; then
            echo ""
            echo -e "  ${GREEN}[OK] Workgroup is available!${NC}"
            break
        elif [ "$STATUS" = "NOTFOUND" ] || [ "$STATUS" = "FAILED" ]; then
            echo ""
            echo -e "  ${RED}[FAILED] Workgroup creation failed${NC}"
            break
        fi
        
        # Progress indicator
        echo -n "."
        sleep 10
    done
    echo ""
fi

# ==========================================
# Get Redshift endpoint
# ==========================================
echo ""
REDSHIFT_ENDPOINT=$(aws redshift-serverless get-workgroup \
    --workgroup-name "$REDSHIFT_WORKGROUP" \
    --query 'workgroup.endpoint.address' --output text 2>/dev/null || echo "pending")

echo "  Redshift Connection Info:"
echo "  ========================="
echo "  Host:     $REDSHIFT_ENDPOINT"
echo "  Port:     5439"
echo "  Database: $REDSHIFT_DATABASE"
echo "  User:     $REDSHIFT_ADMIN_USER"
echo ""

# Save for other scripts
cat > /tmp/redshift_config.sh << EOF
export REDSHIFT_HOST="$REDSHIFT_ENDPOINT"
export REDSHIFT_PORT="5439"
export REDSHIFT_USER="$REDSHIFT_ADMIN_USER"
# REDSHIFT_PASSWORD not saved - set via environment variable
export REDSHIFT_DATABASE="$REDSHIFT_DATABASE"
EOF

echo -e "${GREEN}Step 9 Complete: Redshift Serverless Created${NC}"

fi
