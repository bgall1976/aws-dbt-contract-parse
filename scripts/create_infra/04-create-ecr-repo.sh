#!/bin/bash
# ==========================================
# Step 4: Create ECR Repository
# ==========================================

# Inline configuration
AWS_REGION="${AWS_REGION:-us-east-2}"
PROJECT_NAME="${PROJECT_NAME:-contract-pipeline}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
ECR_REPO_NAME="${PROJECT_NAME}-${ENVIRONMENT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Step 4: Creating ECR Repository...${NC}"
echo "  Region: $AWS_REGION"
echo "  Repository Name: $ECR_REPO_NAME"

# Check if repository exists
ECR_EXISTS=$(aws ecr describe-repositories \
    --repository-names "$ECR_REPO_NAME" \
    --region "$AWS_REGION" \
    --query 'repositories[0].repositoryUri' \
    --output text 2>/dev/null)

if [ -n "$ECR_EXISTS" ] && [ "$ECR_EXISTS" != "None" ]; then
    echo -e "  ${GREEN}[OK] Repository already exists${NC}"
    ECR_REPO_URI="$ECR_EXISTS"
else
    echo "  Creating ECR repository..."
    
    ECR_REPO_URI=$(aws ecr create-repository \
        --repository-name "$ECR_REPO_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --region "$AWS_REGION" \
        --query 'repository.repositoryUri' \
        --output text 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$ECR_REPO_URI" ]; then
        echo -e "  ${GREEN}[OK] Created ECR repository${NC}"
        
        # Set lifecycle policy
        aws ecr put-lifecycle-policy \
            --repository-name "$ECR_REPO_NAME" \
            --region "$AWS_REGION" \
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
            }' > /dev/null 2>&1
        echo -e "  ${GREEN}[OK] Lifecycle policy set${NC}"
    else
        echo -e "  ${RED}[FAILED] Could not create ECR repository${NC}"
        echo "  Error: $ECR_REPO_URI"
    fi
fi

echo ""
echo "  Repository URI: $ECR_REPO_URI"
echo ""
echo "To push images to this repository:"
echo "  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI"
echo "  docker build -t $ECR_REPO_NAME ./extraction"
echo "  docker tag $ECR_REPO_NAME:latest $ECR_REPO_URI:latest"
echo "  docker push $ECR_REPO_URI:latest"
echo ""
echo -e "${GREEN}Step 4 Complete: ECR Repository Created${NC}"
