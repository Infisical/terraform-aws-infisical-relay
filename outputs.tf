# Relay Server Details
output "relay_server_details" {
  value = {
    for name, instance in var.relay_instances : name => {
      public_ip        = aws_eip.relay_server[name].public_ip
      asg_name         = aws_autoscaling_group.relay_server[name].name
      endpoint         = "${aws_eip.relay_server[name].public_ip}:8443"
      eip_allocation_id = aws_eip.relay_server[name].id
    }
  }
  description = "Relay server details with fixed name-to-IP mapping"
}

# Documentation-Ready Endpoints
output "relay_endpoints_for_docs" {
  value = {
    for name, instance in var.relay_instances : name => "${aws_eip.relay_server[name].public_ip}:8443"
  }
  description = "Relay endpoints ready for documentation"
}

# Security Group ID
output "relay_security_group_id" {
  value       = aws_security_group.relay_server.id
  description = "Security group ID for relay servers"
}

# EIP Allocation IDs
output "relay_eip_allocation_ids" {
  value = {
    for name, instance in var.relay_instances : name => aws_eip.relay_server[name].id
  }
  description = "EIP allocation IDs for relay servers"
}

# Auto Scaling Group Names
output "relay_asg_names" {
  value = {
    for name, instance in var.relay_instances : name => aws_autoscaling_group.relay_server[name].name
  }
  description = "Auto Scaling Group names for relay servers"
}

# Launch Template IDs
output "relay_launch_template_ids" {
  value = {
    for name, instance in var.relay_instances : name => aws_launch_template.relay_server[name].id
  }
  description = "Launch template IDs for relay servers"
}

# IAM Role ARN
output "relay_iam_role_arn" {
  value       = aws_iam_role.relay_server.arn
  description = "IAM role ARN for relay servers"
}
