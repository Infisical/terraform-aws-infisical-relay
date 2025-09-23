# Required Variables

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "relay_instances" {
  description = "Map of relay instances with their configuration"
  type = map(object({
    index    = number
    az_index = number
  }))
  
  validation {
    condition = length(var.relay_instances) > 0
    error_message = "At least one relay instance must be defined."
  }
}

variable "vpc_id" {
  description = "VPC ID where relay servers will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for relay server deployment"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "primary_region" {
  description = "Primary AWS region where main infrastructure is hosted (used for shared resources like SSM parameters)"
  type        = string
  default     = "eu-central-1"
}

variable "ami_id" {
  description = "AMI ID for relay server instances"
  type        = string
}

# Optional Variables with Defaults

variable "instance_type" {
  description = "EC2 instance type for relay servers"
  type        = string
  default     = "t3.small"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access relay servers"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "infisical_domain" {
  description = "Infisical domain URL"
  type        = string
  default     = "https://eu.infisical.com"
}

variable "relay_auth_secret_parameter" {
  description = "SSM parameter name containing the relay auth secret"
  type        = string
  default     = "/infisical-relay/INFISICAL_RELAY_AUTH_SECRET"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
