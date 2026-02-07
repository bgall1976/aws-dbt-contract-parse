# ==========================================
# PDF Contract Pipeline - Terraform Configuration
# ==========================================

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "terraform-state-contract-pipeline"
    key            = "contract-pipeline/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "contract-pipeline"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ==========================================
# Data Sources
# ==========================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==========================================
# S3 Buckets
# ==========================================

module "s3_raw" {
  source = "./modules/s3"
  
  bucket_name = "${var.project_name}-raw-${var.environment}"
  
  enable_versioning    = true
  enable_encryption    = true
  enable_lifecycle     = true
  
  lifecycle_rules = [
    {
      id      = "archive-old-contracts"
      enabled = true
      
      transition = [
        {
          days          = 90
          storage_class = "STANDARD_IA"
        },
        {
          days          = 365
          storage_class = "GLACIER"
        }
      ]
    }
  ]
  
  # Event notification for new PDFs
  enable_event_notification = true
  event_queue_arn          = module.sqs_extraction_trigger.queue_arn
  event_filter_suffix      = ".pdf"
}

module "s3_processed" {
  source = "./modules/s3"
  
  bucket_name = "${var.project_name}-processed-${var.environment}"
  
  enable_versioning    = true
  enable_encryption    = true
  enable_lifecycle     = false
}

# ==========================================
# SQS Queue for Extraction Triggers
# ==========================================

module "sqs_extraction_trigger" {
  source = "./modules/sqs"
  
  queue_name = "${var.project_name}-extraction-trigger-${var.environment}"
  
  visibility_timeout_seconds = 900  # 15 minutes
  message_retention_seconds  = 86400  # 1 day
  
  enable_dead_letter_queue = true
  max_receive_count        = 3
}

# ==========================================
# ECR Repository
# ==========================================

module "ecr" {
  source = "./modules/ecr"
  
  repository_name = "${var.project_name}-extractor"
  
  image_tag_mutability = "MUTABLE"
  scan_on_push        = true
  
  lifecycle_policy = {
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  }
}

# ==========================================
# ECS Cluster and Service
# ==========================================

module "ecs" {
  source = "./modules/ecs"
  
  cluster_name = "${var.project_name}-cluster-${var.environment}"
  service_name = "${var.project_name}-extractor-${var.environment}"
  
  # Task configuration
  cpu    = 512
  memory = 1024
  
  container_image = "${module.ecr.repository_url}:latest"
  
  environment_variables = {
    S3_RAW_BUCKET       = module.s3_raw.bucket_name
    S3_PROCESSED_BUCKET = module.s3_processed.bucket_name
    AWS_REGION          = var.aws_region
  }
  
  # Networking
  vpc_id          = var.vpc_id
  subnet_ids      = var.private_subnet_ids
  security_groups = [module.ecs_security_group.security_group_id]
  
  # Auto scaling
  min_capacity = 0
  max_capacity = 5
  
  # SQS trigger
  sqs_queue_arn = module.sqs_extraction_trigger.queue_arn
}

module "ecs_security_group" {
  source = "./modules/security_group"
  
  name        = "${var.project_name}-ecs-sg-${var.environment}"
  description = "Security group for ECS extraction tasks"
  vpc_id      = var.vpc_id
  
  egress_rules = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

# ==========================================
# Redshift Serverless
# ==========================================

module "redshift" {
  source = "./modules/redshift"
  
  namespace_name = "${var.project_name}-${var.environment}"
  workgroup_name = "${var.project_name}-workgroup-${var.environment}"
  
  database_name = "contracts_dw"
  admin_username = var.redshift_admin_username
  admin_password = var.redshift_admin_password
  
  base_capacity = 8  # RPU
  
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids
  
  # Allow access from ECS tasks
  allowed_security_groups = [module.ecs_security_group.security_group_id]
}

# ==========================================
# IAM Roles
# ==========================================

module "ecs_task_role" {
  source = "./modules/iam"
  
  role_name = "${var.project_name}-ecs-task-role-${var.environment}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  
  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]
  
  inline_policies = {
    s3_access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:ListBucket"
          ]
          Resource = [
            module.s3_raw.bucket_arn,
            "${module.s3_raw.bucket_arn}/*"
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:ListBucket"
          ]
          Resource = [
            module.s3_processed.bucket_arn,
            "${module.s3_processed.bucket_arn}/*"
          ]
        }
      ]
    })
    
    sqs_access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "sqs:ReceiveMessage",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes"
          ]
          Resource = module.sqs_extraction_trigger.queue_arn
        }
      ]
    })
  }
}

# ==========================================
# Outputs
# ==========================================

output "s3_raw_bucket" {
  value = module.s3_raw.bucket_name
}

output "s3_processed_bucket" {
  value = module.s3_processed.bucket_name
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "redshift_endpoint" {
  value     = module.redshift.endpoint
  sensitive = true
}
