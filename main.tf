# Infisical Relay Module
# This module creates Infisical relay servers with fixed IP assignments

locals {
  relay_port      = 8443
  ssh_tunnel_port = 2222
}

# =============================================================================
# MONITORING RESOURCES
# =============================================================================

# CloudWatch Log Group for relay service logs
resource "aws_cloudwatch_log_group" "relay_logs" {
  count = var.enable_monitoring ? 1 : 0

  name              = "/infisical-relay/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-relay-logs"
  })
}

# CloudWatch Metric Filter - detects service failures in logs
resource "aws_cloudwatch_log_metric_filter" "relay_service_failed" {
  count = var.enable_monitoring ? 1 : 0

  name           = "${var.name_prefix}-relay-service-failed"
  log_group_name = aws_cloudwatch_log_group.relay_logs[0].name

  # Match systemd/service failure patterns
  # Using CloudWatch Logs filter pattern syntax: ?term1 ?term2 means OR
  pattern = "?\"Failed\" ?\"failed\" ?\"failure\" ?\"exited\" ?\"killed\" ?\"fatal\" ?\"crash\" ?\"Main process exited\" ?\"inactive (dead)\" ?\"entered failed state\""

  metric_transformation {
    name          = "RelayServiceFailure"
    namespace     = "Infisical/Relay"
    value         = "1"
    default_value = "0"
    dimensions = {
      RelayPrefix = var.name_prefix
    }
  }
}

# CloudWatch Alarm - triggers when service failure is detected
resource "aws_cloudwatch_metric_alarm" "relay_service_failed" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.name_prefix}-relay-service-failed"
  alarm_description   = "Alerts when the infisical-relay service fails on any relay instance"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RelayServiceFailure"
  namespace           = "Infisical/Relay"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    RelayPrefix = var.name_prefix
  }

  alarm_actions = var.alarm_sns_topic_arns
  ok_actions    = var.alarm_sns_topic_arns

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-relay-service-alarm"
  })
}

# IAM role for relay instances
resource "aws_iam_role" "relay_server" {
  name = "${var.name_prefix}-relay-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for relay servers
resource "aws_iam_role_policy" "relay_server" {
  name = "${var.name_prefix}-relay-policy"
  role = aws_iam_role.relay_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter*",
          "ssm:DescribeParameters",
          "ec2:DescribeInstances",
          "ec2:DescribeAddresses",
          "ec2:AssociateAddress",
          "ec2:DisassociateAddress"
        ]
        Resource = "*"
      }
      ],
      var.enable_monitoring ? [
        {
          Sid    = "CloudWatchLogsWrite"
          Effect = "Allow"
          Action = [
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:DescribeLogStreams"
          ]
          Resource = "${aws_cloudwatch_log_group.relay_logs[0].arn}:*"
        },
        {
          Sid    = "CloudWatchLogsDescribe"
          Effect = "Allow"
          Action = [
            "logs:DescribeLogGroups"
          ]
          Resource = "arn:aws:logs:${var.aws_region}:*:log-group:*"
        }
    ] : [])
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "relay_server" {
  name = "${var.name_prefix}-relay-profile"
  role = aws_iam_role.relay_server.name

  tags = var.tags
}

# Elastic IPs for relay servers - one per named relay
resource "aws_eip" "relay_server" {
  for_each = var.relay_instances
  domain   = "vpc"

  tags = merge(var.tags, {
    Name      = "${each.key}-eip"
    RelayName = each.key
    Index     = each.value.index
  })
}

# Security group for relay servers
resource "aws_security_group" "relay_server" {
  name        = "${var.name_prefix}-relay-sg"
  description = "Security group for Infisical Relay servers"
  vpc_id      = var.vpc_id

  # Inbound: Platform-to-relay communication (TLS)
  ingress {
    from_port   = local.relay_port
    to_port     = local.relay_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Platform-to-relay communication"
  }

  # Inbound: SSH reverse tunnel from gateways
  ingress {
    from_port   = local.ssh_tunnel_port
    to_port     = local.ssh_tunnel_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "SSH reverse tunnel from gateways"
  }

  # Inbound: SSH access for administration
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access for administration"
  }

  # Outbound: All traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-relay-sg"
  })
}

# Launch template for relay servers
resource "aws_launch_template" "relay_server" {
  for_each = var.relay_instances

  name_prefix   = "${each.key}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.relay_server.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.relay_server.name
  }

  user_data = base64encode(templatefile("${path.module}/relay-user-data.sh", {
    relay_name                  = each.key
    region                      = var.aws_region
    primary_region              = var.primary_region
    infisical_domain            = var.infisical_domain
    relay_auth_secret_parameter = var.relay_auth_secret_parameter
    eip_allocation_id           = aws_eip.relay_server[each.key].id
    # Monitoring configuration
    enable_monitoring    = var.enable_monitoring ? "true" : "false"
    cloudwatch_log_group = var.enable_monitoring ? aws_cloudwatch_log_group.relay_logs[0].name : ""
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name      = each.key
      Type      = "infisical-relay"
      RelayName = each.key
      Index     = each.value.index
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for each relay (min=1, max=1, desired=1)
resource "aws_autoscaling_group" "relay_server" {
  for_each = var.relay_instances

  name                = "${each.key}-asg"
  vpc_zone_identifier = [var.public_subnet_ids[each.value.az_index % length(var.public_subnet_ids)]]

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.relay_server[each.key].id
    version = "$Latest"
  }

  # Health check settings for relay servers
  health_check_type         = "EC2"
  health_check_grace_period = 300
  default_cooldown          = 300

  # Ensure instances are replaced if they become unhealthy
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  tag {
    key                 = "Name"
    value               = "${each.key}-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "RelayName"
    value               = each.key
    propagate_at_launch = false
  }

  tag {
    key                 = "Type"
    value               = "infisical-relay-asg"
    propagate_at_launch = false
  }

  lifecycle {
    create_before_destroy = true
  }
}
