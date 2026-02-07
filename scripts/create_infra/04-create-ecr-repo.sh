#!/bin/bash
# ==========================================
# Step 4: Create ECR Repository
# ==========================================

#set -e  # Disabled - handle errors individually

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo -e "${YELLOW}Step 4: Creating ECR Repository...${NC}"

# Check if repository exists
ecr_exists() {
    aws ecr describe-repositories --repository-names "$1" 2>/dev/null && return 0 || return 1
}

if ecr_exists "$ECR_REPO_NAME"; then
    echo "  ECR repository $ECR_REPO_NAME already exists, skipping..."
else
    echo "  Creating ECR repository: $ECR_REPO_NAME"
    aws ecr create-repository \
        --repository-name "$ECR_REPO_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    
    # Set lifecycle policy to keep only last 10 images
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

# Get repository URI
ECR_REPO_URI=$(aws ecr describe-repositories \
    --repository-names "$ECR_REPO_NAME" \
    --query 'repositories[0].repositoryUri' --output text)

echo "  Repository URI: $ECR_REPO_URI"

# Save for other scripts
echo "export ECR_REPO_URI=\"$ECR_REPO_URI\"" > /tmp/ecr_config.sh

echo ""
echo "To push images to this repository:"
echo "  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI"
echo "  docker build -t $ECR_REPO_NAME ./extraction"
echo "  docker tag $ECR_REPO_NAME:latest $ECR_REPO_URI:latest"
echo "  docker push $ECR_REPO_URI:latest"

echo -e "${GREEN}Step 4 Complete: ECR Repository Created${NC}"
