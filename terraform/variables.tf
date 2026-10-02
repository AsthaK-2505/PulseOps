variable "aws_region" {
  description = "AWS region for PulseOps"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "pulseops"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the PulseOps VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "eks_version" {
  description = "Target Kubernetes version for EKS"
  type        = string
  default     = "1.33"
}
