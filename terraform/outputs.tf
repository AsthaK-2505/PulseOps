output "project_name" {
  description = "PulseOps project name"
  value       = var.project_name
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "aws_region" {
  description = "Target AWS region"
  value       = var.aws_region
}

output "architecture" {
  description = "Target AWS architecture"
  value = {
    networking         = "Amazon VPC"
    load_balancer      = "Application Load Balancer"
    compute            = "Amazon EKS"
    container_registry = "Amazon ECR"
    database           = "Amazon RDS PostgreSQL"
    dns                = "Amazon Route 53"
    monitoring         = "Amazon CloudWatch"
    identity           = "AWS IAM"
  }
}
