#!/bin/bash
# ==========================================
# Teardown Step 11: Display Summary
# ==========================================

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo ""
echo -e "${GREEN}=========================================="
echo "Infrastructure Teardown Complete!"
echo -e "==========================================${NC}"
echo ""
echo "The following resources have been deleted:"
echo "  ✓ ECS Services"
echo "  ✓ ECS Task Definitions"
echo "  ✓ ECS Cluster"
echo "  ✓ Redshift Serverless (Workgroup + Namespace)"
echo "  ✓ ECR Repository"
echo "  ✓ S3 Buckets (Raw + Processed)"
echo "  ✓ SQS Queues (Main + DLQ)"
echo "  ✓ IAM Roles"
echo "  ✓ CloudWatch Log Groups"
echo "  ✓ Security Groups"
echo ""
echo -e "${YELLOW}Note: Some resources may take a few minutes to fully delete.${NC}"
echo "Check the AWS Console to verify all resources are removed."
echo ""

# Clean up temp files
rm -f /tmp/pipeline-config.env 2>/dev/null || true
rm -f /tmp/sqs_config.sh 2>/dev/null || true
rm -f /tmp/ecr_config.sh 2>/dev/null || true
rm -f /tmp/iam_config.sh 2>/dev/null || true
rm -f /tmp/redshift_config.sh 2>/dev/null || true

echo "Removed temporary configuration files."
