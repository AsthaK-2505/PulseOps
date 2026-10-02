locals {
  project_name = var.project_name
  environment  = var.environment

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}

# Target AWS architecture for PulseOps:
#
# Route 53
#     |
#     v
# Application Load Balancer
#     |
#     v
# Amazon EKS
#     |
#     +--> API Gateway
#     +--> Product Service
#     +--> Order Service
#     +--> Notification Service
#     |
#     +--> RabbitMQ
#
# Amazon RDS PostgreSQL provides the production database.
#
# Amazon ECR stores the Docker images.
#
# CloudWatch provides AWS-side infrastructure monitoring.
#
# IAM provides permissions and least-privilege access.
#
# VPC provides the network boundary.
