# ==========================================
# Variables
# ==========================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "contract-pipeline"
}

# ==========================================
# Networking
# ==========================================

variable "vpc_id" {
  description = "VPC ID for resources"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS and Redshift"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (if needed for NAT)"
  type        = list(string)
  default     = []
}

# ==========================================
# Redshift
# ==========================================

variable "redshift_admin_username" {
  description = "Redshift admin username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "redshift_admin_password" {
  description = "Redshift admin password"
  type        = string
  sensitive   = true
}

# ==========================================
# ECS
# ==========================================

variable "ecs_cpu" {
  description = "CPU units for ECS task"
  type        = number
  default     = 512
}

variable "ecs_memory" {
  description = "Memory (MB) for ECS task"
  type        = number
  default     = 1024
}

# ==========================================
# Tags
# ==========================================

variable "additional_tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
