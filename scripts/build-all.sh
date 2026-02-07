#!/bin/bash
# ==========================================
# PDF Contract Pipeline - Build All Infrastructure
# Runs all build scripts in order
# ==========================================

# Don't use set -e - we handle errors in each script

SCRIPT_DIR="$(dirname "$0")/build"

echo "=========================================="
echo "PDF Contract Pipeline - Full Build"
echo "=========================================="
echo ""
echo "This will create all AWS infrastructure."
echo ""

# Make all scripts executable
chmod +x "$SCRIPT_DIR"/*.sh

# Run all scripts in order
"$SCRIPT_DIR/00-config.sh"
"$SCRIPT_DIR/01-create-s3-buckets.sh"
"$SCRIPT_DIR/02-create-sqs-queue.sh"
"$SCRIPT_DIR/03-configure-s3-events.sh"
"$SCRIPT_DIR/04-create-ecr-repo.sh"
"$SCRIPT_DIR/05-create-iam-roles.sh"
"$SCRIPT_DIR/06-create-cloudwatch-logs.sh"
"$SCRIPT_DIR/07-create-ecs-cluster.sh"
"$SCRIPT_DIR/08-create-ecs-task-definition.sh"
"$SCRIPT_DIR/09-create-redshift.sh"
"$SCRIPT_DIR/10-summary.sh"
