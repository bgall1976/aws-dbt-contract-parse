#!/bin/bash
# ==========================================
# PDF Contract Pipeline - Teardown All Infrastructure
# Runs all teardown scripts in order
# WARNING: This will DELETE all resources!
# ==========================================

SCRIPT_DIR="$(dirname "$0")/teardown"

# Colors
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}=========================================="
echo "PDF Contract Pipeline - Full Teardown"
echo -e "==========================================${NC}"
echo ""
echo -e "${RED}WARNING: This will DELETE all AWS resources!${NC}"
echo ""
echo "The following will be deleted:"
echo "  - S3 Buckets (and all contents)"
echo "  - SQS Queues"
echo "  - ECR Repository (and all images)"
echo "  - ECS Cluster, Services, Task Definitions"
echo "  - Redshift Serverless"
echo "  - IAM Roles"
echo "  - CloudWatch Log Groups"
echo "  - Security Groups"
echo ""

# Confirmation prompt
read -p "Are you sure you want to DELETE all resources? Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Teardown cancelled."
    exit 0
fi

echo ""
echo "Starting teardown..."
echo ""

# Make all scripts executable
chmod +x "$SCRIPT_DIR"/*.sh

# Run all scripts in order (continue on error for teardown)
"$SCRIPT_DIR/00-config.sh" || true
"$SCRIPT_DIR/01-delete-ecs-services.sh" || true
"$SCRIPT_DIR/02-delete-ecs-task-definitions.sh" || true
"$SCRIPT_DIR/03-delete-ecs-cluster.sh" || true
"$SCRIPT_DIR/04-delete-redshift.sh" || true
"$SCRIPT_DIR/05-delete-ecr-repo.sh" || true
"$SCRIPT_DIR/06-delete-s3-buckets.sh" || true
"$SCRIPT_DIR/07-delete-sqs-queues.sh" || true
"$SCRIPT_DIR/08-delete-iam-roles.sh" || true
"$SCRIPT_DIR/09-delete-cloudwatch-logs.sh" || true
"$SCRIPT_DIR/10-delete-security-groups.sh" || true
"$SCRIPT_DIR/11-summary.sh" || true
