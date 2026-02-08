#!/bin/bash
# ==========================================
# Step 9: Create Redshift Serverless
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REDSHIFT_ADMIN_USER="${REDSHIFT_ADMIN_USER:-admin}"
REDSHIFT_ADMIN_PASSWORD="${REDSHIFT_ADMIN_PASSWORD:-}"
REDSHIFT_DATABASE="${REDSHIFT_DATABASE:-contracts_dw}"

# Derived names
REDSHIFT_NAMESPACE="${PROJECT_NAME}-${ENVIRONMENT}"
REDSHIFT_WORKGROUP="${PROJECT_NAME}-workgroup-${ENVIRONMENT}"
SECURITY_GROUP_NAME="${PROJECT_NAME}-redshift-sg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 9: Creating Redshift Serverless...${NC}"
echo ""
echo "  Region: $AWS_REGION"
echo "  Namespace: $REDSHIFT_NAMESPACE"
echo "  Workgroup: $REDSHIFT_WORKGROUP"
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
# Create Security Group
# ==========================================
echo "Creating/finding security group..."

DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --region "$AWS_REGION" \
    --output text)

echo "  VPC: $DEFAULT_VPC_ID"

SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SECURITY_GROUP_NAME}" "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
    --query 'SecurityGroups[0].GroupId' \
    --region "$AWS_REGION" \
    --output text 2>/dev/null)

if [ -z "$SECURITY_GROUP_ID" ] || [ "$SECURITY_GROUP_ID" == "None" ]; then
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "${SECURITY_GROUP_NAME}" \
        --description "Security group for Redshift Serverless" \
        --vpc-id "$DEFAULT_VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' \
        --output text 2>/dev/null)
    echo -e "  ${GREEN}[OK] Created security group: $SECURITY_GROUP_ID${NC}"
    
    # Allow inbound on port 5439
    aws ec2 authorize-security-group-ingress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 5439 \
        --cidr "0.0.0.0/0" \
        --region "$AWS_REGION" > /dev/null 2>&1
    echo "  Added ingress rule for port 5439"
else
    echo -e "  ${GREEN}[OK] Security group exists: $SECURITY_GROUP_ID${NC}"
fi

# ==========================================
# Create Namespace
# ==========================================
echo ""
echo "Checking if namespace exists..."
NAMESPACE_EXISTS=$(aws redshift-serverless get-namespace \
    --namespace-name "${REDSHIFT_NAMESPACE}" \
    --region "$AWS_REGION" \
    --query "namespace.namespaceName" \
    --output text 2>/dev/null)

if [ -n "$NAMESPACE_EXISTS" ] && [ "$NAMESPACE_EXISTS" != "None" ]; then
    echo -e "  ${GREEN}[OK] Namespace already exists${NC}"
else
    echo "  Creating namespace: $REDSHIFT_NAMESPACE"
    
    aws redshift-serverless create-namespace \
        --namespace-name "$REDSHIFT_NAMESPACE" \
        --admin-username "$REDSHIFT_ADMIN_USER" \
        --admin-user-password "$REDSHIFT_ADMIN_PASSWORD" \
        --db-name "$REDSHIFT_DATABASE" \
        --region "$AWS_REGION" \
        --output text > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}[OK] Created namespace${NC}"
    else
        echo -e "  ${RED}[FAILED] Failed to create namespace${NC}"
    fi
    
    # Wait for namespace to be available
    echo "  Waiting for namespace to be available..."
    for i in {1..30}; do
        STATUS=$(aws redshift-serverless get-namespace \
            --namespace-name "$REDSHIFT_NAMESPACE" \
            --region "$AWS_REGION" \
            --query "namespace.status" \
            --output text 2>/dev/null || echo "NOTFOUND")
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
WORKGROUP_EXISTS=$(aws redshift-serverless get-workgroup \
    --workgroup-name "${REDSHIFT_WORKGROUP}" \
    --region "$AWS_REGION" \
    --query "workgroup.workgroupName" \
    --output text 2>/dev/null)

if [ -n "$WORKGROUP_EXISTS" ] && [ "$WORKGROUP_EXISTS" != "None" ]; then
    echo -e "  ${GREEN}[OK] Workgroup already exists${NC}"
else
    echo "  Creating workgroup: $REDSHIFT_WORKGROUP"
    
    # Get subnets
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
        --query 'Subnets[*].SubnetId' \
        --region "$AWS_REGION" \
        --output text)
    
    echo "  Subnets: $SUBNET_IDS"
    
    aws redshift-serverless create-workgroup \
        --workgroup-name "$REDSHIFT_WORKGROUP" \
        --namespace-name "$REDSHIFT_NAMESPACE" \
        --base-capacity 8 \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --subnet-ids $SUBNET_IDS \
        --publicly-accessible \
        --region "$AWS_REGION" \
        --output text > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}[OK] Workgroup creation started${NC}"
    else
        echo -e "  ${RED}[FAILED] Failed to create workgroup${NC}"
    fi
    
    # Wait for workgroup to be available
    echo ""
    echo "  Waiting for workgroup to become available..."
    echo "  (This typically takes 5-10 minutes)"
    echo ""
    for i in {1..60}; do
        STATUS=$(aws redshift-serverless get-workgroup \
            --workgroup-name "$REDSHIFT_WORKGROUP" \
            --region "$AWS_REGION" \
            --query "workgroup.status" \
            --output text 2>/dev/null || echo "NOTFOUND")
        
        if [ "$STATUS" = "AVAILABLE" ]; then
            echo ""
            echo -e "  ${GREEN}[OK] Workgroup is available!${NC}"
            break
        elif [ "$STATUS" = "NOTFOUND" ] || [ "$STATUS" = "FAILED" ]; then
            echo ""
            echo -e "  ${RED}[FAILED] Workgroup creation failed${NC}"
            break
        fi
        
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
    --region "$AWS_REGION" \
    --query 'workgroup.endpoint.address' \
    --output text 2>/dev/null || echo "pending")

echo "  Redshift Connection Info:"
echo "  ========================="
echo "  Host:     $REDSHIFT_ENDPOINT"
echo "  Port:     5439"
echo "  Database: $REDSHIFT_DATABASE"
echo "  User:     $REDSHIFT_ADMIN_USER"
echo ""
echo -e "${GREEN}Step 9 Complete: Redshift Serverless Created${NC}"

fi
