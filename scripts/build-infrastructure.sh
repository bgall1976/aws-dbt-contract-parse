#!/bin/bash
# ==========================================
# PDF Contract Pipeline - AWS Infrastructure Build Script
# Run this in AWS CloudShell
# ==========================================

#set -e  # Disabled - handle errors individually  # Exit on any error

# ==========================================
# Configuration - EDIT THESE VALUES
# ==========================================
PROJECT_NAME="contract-pipeline"
AWS_REGION="us-east-1"
ENVIRONMENT="dev"

# Redshift credentials (CHANGE THESE!)
REDSHIFT_ADMIN_USER="admin"
REDSHIFT_ADMIN_PASSWORD="${REDSHIFT_ADMIN_PASSWORD:-CHANGE_ME_BEFORE_RUNNING}"  # Set this via environment variable!
REDSHIFT_DATABASE="contracts_dw"

# ==========================================
# Derived names
# ==========================================
S3_RAW_BUCKET="${PROJECT_NAME}-raw-${ENVIRONMENT}-$(aws sts get-caller-identity --query Account --output text)"
S3_PROCESSED_BUCKET="${PROJECT_NAME}-processed-${ENVIRONMENT}-$(aws sts get-caller-identity --query Account --output text)"
ECR_REPO_NAME="${PROJECT_NAME}-extractor"
ECS_CLUSTER_NAME="${PROJECT_NAME}-cluster-${ENVIRONMENT}"
ECS_SERVICE_NAME="${PROJECT_NAME}-extractor-service"
ECS_TASK_FAMILY="${PROJECT_NAME}-extractor-task"
SQS_QUEUE_NAME="${PROJECT_NAME}-extraction-trigger-${ENVIRONMENT}"
REDSHIFT_NAMESPACE="${PROJECT_NAME}-${ENVIRONMENT}"
REDSHIFT_WORKGROUP="${PROJECT_NAME}-workgroup-${ENVIRONMENT}"
IAM_ROLE_NAME="${PROJECT_NAME}-ecs-task-role-${ENVIRONMENT}"
IAM_EXECUTION_ROLE_NAME="${PROJECT_NAME}-ecs-execution-role-${ENVIRONMENT}"
LOG_GROUP_NAME="/ecs/${PROJECT_NAME}-${ENVIRONMENT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================="
echo "PDF Contract Pipeline - Infrastructure Setup"
echo -e "==========================================${NC}"
echo ""
echo "Project: ${PROJECT_NAME}"
echo "Region: ${AWS_REGION}"
echo "Environment: ${ENVIRONMENT}"
echo ""

# ==========================================
# Function: Check if resource exists
# ==========================================
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "s3")
            aws s3api head-bucket --bucket "$resource_name" 2>/dev/null && return 0 || return 1
            ;;
        "ecr")
            aws ecr describe-repositories --repository-names "$resource_name" 2>/dev/null && return 0 || return 1
            ;;
        "ecs-cluster")
            aws ecs describe-clusters --clusters "$resource_name" --query "clusters[?status=='ACTIVE']" --output text 2>/dev/null | grep -q "$resource_name" && return 0 || return 1
            ;;
        "sqs")
            aws sqs get-queue-url --queue-name "$resource_name" 2>/dev/null && return 0 || return 1
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" 2>/dev/null && return 0 || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# ==========================================
# Step 1: Create S3 Buckets
# ==========================================
echo -e "${YELLOW}Step 1: Creating S3 Buckets...${NC}"

# Raw bucket
if resource_exists "s3" "$S3_RAW_BUCKET"; then
    echo "  S3 bucket $S3_RAW_BUCKET already exists, skipping..."
else
    echo "  Creating S3 bucket: $S3_RAW_BUCKET"
    aws s3api create-bucket \
        --bucket "$S3_RAW_BUCKET" \
        --region "$AWS_REGION" \
        $(if [ "$AWS_REGION" != "us-east-1" ]; then echo "--create-bucket-configuration LocationConstraint=$AWS_REGION"; fi)
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$S3_RAW_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$S3_RAW_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
        }'
    
    echo -e "  ${GREEN}✓ Created $S3_RAW_BUCKET${NC}"
fi

# Processed bucket
if resource_exists "s3" "$S3_PROCESSED_BUCKET"; then
    echo "  S3 bucket $S3_PROCESSED_BUCKET already exists, skipping..."
else
    echo "  Creating S3 bucket: $S3_PROCESSED_BUCKET"
    aws s3api create-bucket \
        --bucket "$S3_PROCESSED_BUCKET" \
        --region "$AWS_REGION" \
        $(if [ "$AWS_REGION" != "us-east-1" ]; then echo "--create-bucket-configuration LocationConstraint=$AWS_REGION"; fi)
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$S3_PROCESSED_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$S3_PROCESSED_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
        }'
    
    echo -e "  ${GREEN}✓ Created $S3_PROCESSED_BUCKET${NC}"
fi

# ==========================================
# Step 2: Create SQS Queue
# ==========================================
echo -e "${YELLOW}Step 2: Creating SQS Queue...${NC}"

if resource_exists "sqs" "$SQS_QUEUE_NAME"; then
    echo "  SQS queue $SQS_QUEUE_NAME already exists, skipping..."
    SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --query 'QueueUrl' --output text)
else
    echo "  Creating SQS queue: $SQS_QUEUE_NAME"
    
    # Create dead letter queue first
    DLQ_URL=$(aws sqs create-queue \
        --queue-name "${SQS_QUEUE_NAME}-dlq" \
        --query 'QueueUrl' --output text)
    
    DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$DLQ_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    # Create main queue with DLQ
    SQS_QUEUE_URL=$(aws sqs create-queue \
        --queue-name "$SQS_QUEUE_NAME" \
        --attributes '{
            "VisibilityTimeout": "900",
            "MessageRetentionPeriod": "86400",
            "RedrivePolicy": "{\"deadLetterTargetArn\":\"'"$DLQ_ARN"'\",\"maxReceiveCount\":\"3\"}"
        }' \
        --query 'QueueUrl' --output text)
    
    echo -e "  ${GREEN}✓ Created $SQS_QUEUE_NAME${NC}"
fi

SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
    --queue-url "$SQS_QUEUE_URL" \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' --output text)

# ==========================================
# Step 3: Configure S3 Event Notification
# ==========================================
echo -e "${YELLOW}Step 3: Configuring S3 Event Notifications...${NC}"

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Update SQS policy to allow S3 to send messages
echo "  Updating SQS policy for S3 notifications..."
aws sqs set-queue-attributes \
    --queue-url "$SQS_QUEUE_URL" \
    --attributes '{
        "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"s3.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"'"$SQS_QUEUE_ARN"'\",\"Condition\":{\"ArnLike\":{\"aws:SourceArn\":\"arn:aws:s3:::'"$S3_RAW_BUCKET"'\"}}}]}"
    }'

# Configure S3 event notification
echo "  Setting up S3 event notification..."
aws s3api put-bucket-notification-configuration \
    --bucket "$S3_RAW_BUCKET" \
    --notification-configuration '{
        "QueueConfigurations": [{
            "QueueArn": "'"$SQS_QUEUE_ARN"'",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [{"Name": "suffix", "Value": ".pdf"}]
                }
            }
        }]
    }'

echo -e "  ${GREEN}✓ S3 event notification configured${NC}"

# ==========================================
# Step 4: Create ECR Repository
# ==========================================
echo -e "${YELLOW}Step 4: Creating ECR Repository...${NC}"

if resource_exists "ecr" "$ECR_REPO_NAME"; then
    echo "  ECR repository $ECR_REPO_NAME already exists, skipping..."
else
    echo "  Creating ECR repository: $ECR_REPO_NAME"
    aws ecr create-repository \
        --repository-name "$ECR_REPO_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    
    # Set lifecycle policy
    aws ecr put-lifecycle-policy \
        --repository-name "$ECR_REPO_NAME" \
        --lifecycle-policy-text '{
            "rules": [{
                "rulePriority": 1,
                "description": "Keep last 10 images",
                "selection": {
                    "tagStatus": "any",
                    "countType": "imageCountMoreThan",
                    "countNumber": 10
                },
                "action": {"type": "expire"}
            }]
        }'
    
    echo -e "  ${GREEN}✓ Created ECR repository${NC}"
fi

ECR_REPO_URI=$(aws ecr describe-repositories \
    --repository-names "$ECR_REPO_NAME" \
    --query 'repositories[0].repositoryUri' --output text)

# ==========================================
# Step 5: Create IAM Roles
# ==========================================
echo -e "${YELLOW}Step 5: Creating IAM Roles...${NC}"

# Ensure SQS_QUEUE_ARN is set (in case queue already existed)
if [ -z "$SQS_QUEUE_ARN" ]; then
    SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --query 'QueueUrl' --output text 2>/dev/null || echo "")
    if [ -n "$SQS_QUEUE_URL" ]; then
        SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
            --queue-url "$SQS_QUEUE_URL" \
            --attribute-names QueueArn \
            --query 'Attributes.QueueArn' --output text)
    fi
fi

# ECS Task Execution Role
if resource_exists "iam-role" "$IAM_EXECUTION_ROLE_NAME"; then
    echo "  IAM role $IAM_EXECUTION_ROLE_NAME already exists, skipping..."
else
    echo "  Creating ECS Task Execution Role..."
    aws iam create-role \
        --role-name "$IAM_EXECUTION_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "ecs-tasks.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }'
    
    aws iam attach-role-policy \
        --role-name "$IAM_EXECUTION_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    
    echo -e "  ${GREEN}✓ Created ECS Execution Role${NC}"
fi

# ECS Task Role (for application permissions)
if resource_exists "iam-role" "$IAM_ROLE_NAME"; then
    echo "  IAM role $IAM_ROLE_NAME already exists, skipping..."
else
    echo "  Creating ECS Task Role..."
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "ecs-tasks.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }'
    
    # Create and attach custom policy for S3 and SQS access
    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name "ContractPipelineAccess" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["s3:GetObject", "s3:ListBucket"],
                    "Resource": [
                        "arn:aws:s3:::'"$S3_RAW_BUCKET"'",
                        "arn:aws:s3:::'"$S3_RAW_BUCKET"'/*"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
                    "Resource": [
                        "arn:aws:s3:::'"$S3_PROCESSED_BUCKET"'",
                        "arn:aws:s3:::'"$S3_PROCESSED_BUCKET"'/*"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
                    "Resource": "'"$SQS_QUEUE_ARN"'"
                },
                {
                    "Effect": "Allow",
                    "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
                    "Resource": "*"
                }
            ]
        }'
    
    echo -e "  ${GREEN}✓ Created ECS Task Role${NC}"
fi

TASK_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_EXECUTION_ROLE_NAME}"

# ==========================================
# Step 6: Create CloudWatch Log Group
# ==========================================
echo -e "${YELLOW}Step 6: Creating CloudWatch Log Group...${NC}"

aws logs create-log-group --log-group-name "$LOG_GROUP_NAME" 2>/dev/null || echo "  Log group already exists, skipping..."
aws logs put-retention-policy --log-group-name "$LOG_GROUP_NAME" --retention-in-days 30

echo -e "  ${GREEN}✓ CloudWatch Log Group configured${NC}"

# ==========================================
# Step 7: Create ECS Cluster
# ==========================================
echo -e "${YELLOW}Step 7: Creating ECS Cluster...${NC}"

if resource_exists "ecs-cluster" "$ECS_CLUSTER_NAME"; then
    echo "  ECS cluster $ECS_CLUSTER_NAME already exists, skipping..."
else
    echo "  Creating ECS cluster: $ECS_CLUSTER_NAME"
    aws ecs create-cluster \
        --cluster-name "$ECS_CLUSTER_NAME" \
        --capacity-providers FARGATE FARGATE_SPOT \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1
    
    echo -e "  ${GREEN}✓ Created ECS cluster${NC}"
fi

# ==========================================
# Step 8: Register ECS Task Definition
# ==========================================
echo -e "${YELLOW}Step 8: Registering ECS Task Definition...${NC}"

# Create task definition JSON
cat > /tmp/task-definition.json << EOF
{
    "family": "${ECS_TASK_FAMILY}",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "512",
    "memory": "1024",
    "executionRoleArn": "${EXECUTION_ROLE_ARN}",
    "taskRoleArn": "${TASK_ROLE_ARN}",
    "containerDefinitions": [{
        "name": "extractor",
        "image": "${ECR_REPO_URI}:latest",
        "essential": true,
        "environment": [
            {"name": "S3_RAW_BUCKET", "value": "${S3_RAW_BUCKET}"},
            {"name": "S3_PROCESSED_BUCKET", "value": "${S3_PROCESSED_BUCKET}"},
            {"name": "AWS_REGION", "value": "${AWS_REGION}"}
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "${LOG_GROUP_NAME}",
                "awslogs-region": "${AWS_REGION}",
                "awslogs-stream-prefix": "extractor"
            }
        }
    }]
}
EOF

aws ecs register-task-definition --cli-input-json file:///tmp/task-definition.json > /dev/null

echo -e "  ${GREEN}✓ Registered ECS Task Definition${NC}"

# ==========================================
# Step 9: Create Redshift Serverless
# ==========================================
echo -e "${YELLOW}Step 9: Creating Redshift Serverless...${NC}"

# Check if namespace exists
NAMESPACE_EXISTS=$(aws redshift-serverless list-namespaces \
    --query "namespaces[?namespaceName=='${REDSHIFT_NAMESPACE}'].namespaceName" \
    --output text 2>/dev/null || echo "")

if [ -n "$NAMESPACE_EXISTS" ]; then
    echo "  Redshift namespace $REDSHIFT_NAMESPACE already exists, skipping..."
else
    echo "  Creating Redshift Serverless namespace..."
    aws redshift-serverless create-namespace \
        --namespace-name "$REDSHIFT_NAMESPACE" \
        --admin-username "$REDSHIFT_ADMIN_USER" \
        --admin-user-password "$REDSHIFT_ADMIN_PASSWORD" \
        --db-name "$REDSHIFT_DATABASE" \
        --default-iam-role-arn "" \
        --tags key=Project,value="$PROJECT_NAME" key=Environment,value="$ENVIRONMENT"
    
    echo -e "  ${GREEN}✓ Created Redshift namespace${NC}"
fi

# Check if workgroup exists
WORKGROUP_EXISTS=$(aws redshift-serverless list-workgroups \
    --query "workgroups[?workgroupName=='${REDSHIFT_WORKGROUP}'].workgroupName" \
    --output text 2>/dev/null || echo "")

if [ -n "$WORKGROUP_EXISTS" ]; then
    echo "  Redshift workgroup $REDSHIFT_WORKGROUP already exists, skipping..."
else
    echo "  Creating Redshift Serverless workgroup..."
    
    # Get default VPC and subnets
    DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
    SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')
    
    # Create security group for Redshift
    REDSHIFT_SG_ID=$(aws ec2 create-security-group \
        --group-name "${PROJECT_NAME}-redshift-sg" \
        --description "Security group for Redshift Serverless" \
        --vpc-id "$DEFAULT_VPC_ID" \
        --query 'GroupId' --output text 2>/dev/null || \
        aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=${PROJECT_NAME}-redshift-sg" \
            --query 'SecurityGroups[0].GroupId' --output text)
    
    # Allow inbound on port 5439
    aws ec2 authorize-security-group-ingress \
        --group-id "$REDSHIFT_SG_ID" \
        --protocol tcp \
        --port 5439 \
        --cidr "0.0.0.0/0" 2>/dev/null || true
    
    aws redshift-serverless create-workgroup \
        --workgroup-name "$REDSHIFT_WORKGROUP" \
        --namespace-name "$REDSHIFT_NAMESPACE" \
        --base-capacity 8 \
        --security-group-ids "$REDSHIFT_SG_ID" \
        --subnet-ids ${SUBNET_IDS//,/ } \
        --publicly-accessible \
        --tags key=Project,value="$PROJECT_NAME" key=Environment,value="$ENVIRONMENT"
    
    echo "  Waiting for Redshift workgroup to become available (this may take 5-10 minutes)..."
    aws redshift-serverless wait workgroup-available --workgroup-name "$REDSHIFT_WORKGROUP"
    
    echo -e "  ${GREEN}✓ Created Redshift workgroup${NC}"
fi

# Get Redshift endpoint
REDSHIFT_ENDPOINT=$(aws redshift-serverless get-workgroup \
    --workgroup-name "$REDSHIFT_WORKGROUP" \
    --query 'workgroup.endpoint.address' --output text 2>/dev/null || echo "pending")

# ==========================================
# Summary
# ==========================================
echo ""
echo -e "${GREEN}=========================================="
echo "Infrastructure Setup Complete!"
echo -e "==========================================${NC}"
echo ""
echo "Resources Created:"
echo "  S3 Raw Bucket:        $S3_RAW_BUCKET"
echo "  S3 Processed Bucket:  $S3_PROCESSED_BUCKET"
echo "  SQS Queue:            $SQS_QUEUE_NAME"
echo "  ECR Repository:       $ECR_REPO_URI"
echo "  ECS Cluster:          $ECS_CLUSTER_NAME"
echo "  Redshift Namespace:   $REDSHIFT_NAMESPACE"
echo "  Redshift Workgroup:   $REDSHIFT_WORKGROUP"
echo "  Redshift Endpoint:    $REDSHIFT_ENDPOINT"
echo ""
echo "Redshift Connection Info:"
echo "  Host:     $REDSHIFT_ENDPOINT"
echo "  Port:     5439"
echo "  Database: $REDSHIFT_DATABASE"
echo "  User:     $REDSHIFT_ADMIN_USER"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Build and push Docker image to ECR:"
echo "   aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REPO_URI"
echo "   docker build -t $ECR_REPO_NAME ./extraction"
echo "   docker tag $ECR_REPO_NAME:latest $ECR_REPO_URI:latest"
echo "   docker push $ECR_REPO_URI:latest"
echo ""
echo "2. Upload a test PDF to trigger the pipeline:"
echo "   aws s3 cp sample_contract.pdf s3://$S3_RAW_BUCKET/incoming/"
echo ""
echo "3. Set up dbt with these environment variables:"
echo "   export REDSHIFT_HOST=$REDSHIFT_ENDPOINT"
echo "   export REDSHIFT_PORT=5439"
echo "   export REDSHIFT_USER=$REDSHIFT_ADMIN_USER"
echo "   export REDSHIFT_PASSWORD='<your-password-here>'"
echo "   export REDSHIFT_DATABASE=$REDSHIFT_DATABASE"
echo ""

# Save configuration to file
cat > /tmp/pipeline-config.env << EOF
# Contract Pipeline Configuration
# Generated: $(date)

export PROJECT_NAME="${PROJECT_NAME}"
export AWS_REGION="${AWS_REGION}"
export ENVIRONMENT="${ENVIRONMENT}"

# S3
export S3_RAW_BUCKET="${S3_RAW_BUCKET}"
export S3_PROCESSED_BUCKET="${S3_PROCESSED_BUCKET}"

# SQS
export SQS_QUEUE_URL="${SQS_QUEUE_URL}"
export SQS_QUEUE_ARN="${SQS_QUEUE_ARN}"

# ECR
export ECR_REPO_URI="${ECR_REPO_URI}"

# ECS
export ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME}"
export ECS_TASK_FAMILY="${ECS_TASK_FAMILY}"

# Redshift
export REDSHIFT_HOST="${REDSHIFT_ENDPOINT}"
export REDSHIFT_PORT="5439"
export REDSHIFT_USER="${REDSHIFT_ADMIN_USER}"
# REDSHIFT_PASSWORD not saved for security - use environment variable
export REDSHIFT_DATABASE="${REDSHIFT_DATABASE}"
EOF

echo "Configuration saved to: /tmp/pipeline-config.env"
echo "Run 'source /tmp/pipeline-config.env' to load environment variables"
