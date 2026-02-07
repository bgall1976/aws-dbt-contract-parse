#!/bin/bash
# ==========================================
# PDF Contract Pipeline - Cost Estimator
# Run this to see estimated monthly costs
# ==========================================

echo "=========================================="
echo "PDF Contract Pipeline - Cost Estimate"
echo "=========================================="
echo ""

# Configuration
PDFS_PER_MONTH=${1:-100}
EXTRACTION_TIME_PER_PDF=5  # minutes
REDSHIFT_HOURS_PER_DAY=${2:-2}
STORAGE_GB=${3:-10}

# Calculations
ECS_HOURS=$(echo "scale=2; $PDFS_PER_MONTH * $EXTRACTION_TIME_PER_PDF / 60" | bc)
REDSHIFT_HOURS=$(echo "scale=2; $REDSHIFT_HOURS_PER_DAY * 30" | bc)

# Costs
ECS_COST=$(echo "scale=2; $ECS_HOURS * 0.025" | bc)  # 0.5 vCPU + 1GB
REDSHIFT_COST=$(echo "scale=2; $REDSHIFT_HOURS * 3" | bc)  # 8 RPU @ $0.375/RPU-hour
S3_COST=$(echo "scale=2; $STORAGE_GB * 0.023 + 0.005 * $PDFS_PER_MONTH / 1000 * 2" | bc)
SQS_COST=0.01
CLOUDWATCH_COST=2.50
ECR_COST=0.50

TOTAL=$(echo "scale=2; $ECS_COST + $REDSHIFT_COST + $S3_COST + $SQS_COST + $CLOUDWATCH_COST + $ECR_COST" | bc)

echo "Input Parameters:"
echo "  PDFs processed per month: $PDFS_PER_MONTH"
echo "  Redshift hours per day:   $REDSHIFT_HOURS_PER_DAY"
echo "  Storage (GB):             $STORAGE_GB"
echo ""
echo "Calculated Usage:"
echo "  ECS Fargate hours:        $ECS_HOURS hrs"
echo "  Redshift hours:           $REDSHIFT_HOURS hrs"
echo ""
echo "Estimated Monthly Costs:"
echo "  ┌─────────────────────────────────────┐"
echo "  │ Service              │ Cost         │"
echo "  ├─────────────────────────────────────┤"
printf "  │ ECS Fargate          │ \$%-10s │\n" "$ECS_COST"
printf "  │ Redshift Serverless  │ \$%-10s │\n" "$REDSHIFT_COST"
printf "  │ S3 Storage           │ \$%-10s │\n" "$S3_COST"
printf "  │ SQS                  │ \$%-10s │\n" "$SQS_COST"
printf "  │ CloudWatch Logs      │ \$%-10s │\n" "$CLOUDWATCH_COST"
printf "  │ ECR                  │ \$%-10s │\n" "$ECR_COST"
echo "  ├─────────────────────────────────────┤"
printf "  │ TOTAL                │ \$%-10s │\n" "$TOTAL"
echo "  └─────────────────────────────────────┘"
echo ""
echo "Cost Optimization Tips:"
echo "  - Redshift auto-pauses when idle (saves \$\$\$)"
echo "  - Use FARGATE_SPOT for 70% ECS savings"
echo "  - Set S3 lifecycle policies for old files"
echo "  - Consider reserved capacity for steady workloads"
echo ""
echo "Usage: $0 [pdfs_per_month] [redshift_hours_per_day] [storage_gb]"
echo "Example: $0 500 4 50"
