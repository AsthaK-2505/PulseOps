output "project_name" {
  description = "PulseOps project name"
  value       = var.project_name
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "vpc_cidr" {
  description = "PulseOps VPC CIDR"
  value       = aws_vpc.pulseops.cidr_block
}

output "ecr_repositories" {
  description = "ECR repositories for PulseOps services"
  value = {
    for service, repository in aws_ecr_repository.services :
    service => repository.repository_url
  }
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.pulseops.name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.address
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.pulseops.dns_name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group"
  value       = aws_cloudwatch_log_group.pulseops.name
}

output "route53_zone" {
  description = "Route 53 hosted zone"
  value       = aws_route53_zone.pulseops.name
}
