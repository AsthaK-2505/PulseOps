variable "aws_region" {
  description = "AWS region for the PulseOps infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for AWS resource naming"
  type        = string
  default     = "pulseops"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}
