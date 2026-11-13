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
    condition     = length(var.relay_instances) > 0
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

variable "admin_ssh_cidr_blocks" {
  description = "IPv4 CIDR blocks allowed to reach port 22 for administration. Empty keeps port 22 closed."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.admin_ssh_cidr_blocks :
      can(cidrnetmask(cidr)) && try(cidrhost(cidr, 0) == split("/", cidr)[0], false)
    ])
    error_message = "Each entry in admin_ssh_cidr_blocks must be an IPv4 network address in CIDR form with no host bits set, for example 203.0.113.10/32 or 10.0.0.0/8."
  }

  validation {
    condition     = alltrue([for cidr in var.admin_ssh_cidr_blocks : try(tonumber(split("/", cidr)[1]) >= 8, false)])
    error_message = "admin_ssh_cidr_blocks entries must be /8 or narrower."
  }
}

variable "enable_ssm_session_manager" {
  description = "Grant the relay role the minimal Session Manager permissions so instances can be reached through SSM Session Manager. Deliberately not AmazonSSMManagedInstanceCore, which also allows reading every SSM parameter in the account."
  type        = bool
  default     = true
}

variable "infisical_domain" {
  description = "Infisical domain URL"
  type        = string
  default     = "https://eu.infisical.com"
}

variable "relay_auth_secret_parameter" {
  description = "Name of the SSM parameter containing the relay auth secret, in primary_region (for example /infisical-relay/INFISICAL_RELAY_AUTH_SECRET). A plain name only: not an ARN, and no :version or :label suffix."
  type        = string
  default     = "/infisical-relay/INFISICAL_RELAY_AUTH_SECRET"

  # The relay role is granted ssm:GetParameter on the ARN built from this name. An ARN or a
  # version/label selector would build an ARN that matches nothing and the relay would fail at boot.
  validation {
    condition     = can(regex("^/?[A-Za-z0-9_./-]+$", var.relay_auth_secret_parameter))
    error_message = "relay_auth_secret_parameter must be a plain SSM parameter name (letters, numbers, _ . - /), not an ARN or a name:version / name:label selector."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Monitoring Variables

variable "enable_monitoring" {
  description = "Enable CloudWatch-based monitoring. When enabled, relay service logs are shipped to CloudWatch Logs, and a CloudWatch Alarm is created to detect service failures."
  type        = bool
  default     = false
}

variable "alarm_sns_topic_arns" {
  description = "List of SNS topic ARNs to notify when a relay alarm (service failure or CPU) changes state. Pass your existing alerting infrastructure (e.g., PagerDuty-connected SNS topic)."
  type        = list(string)
  default     = []
}

variable "enable_cpu_alarm" {
  description = "Create a CloudWatch CPUUtilization alarm per relay Auto Scaling Group, notifying alarm_sns_topic_arns. Independent of enable_monitoring."
  type        = bool
  default     = false
}

variable "cpu_alarm_threshold" {
  description = "CPUUtilization (%) at or above which the relay CPU alarm fires"
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold must be greater than 0 and at most 100."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch Logs (default: 30)"
  type        = number
  default     = 30
}
