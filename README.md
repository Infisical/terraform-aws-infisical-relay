# Infisical Terraform Relay Module

Deploys Infisical relay servers on AWS. Each entry in `relay_instances` gets its own Elastic IP, launch template and single-instance Auto Scaling Group, so a relay keeps a fixed public IP across instance replacements.

## Usage

```hcl
module "infisical_relay" {
  source = "github.com/Infisical/terraform-aws-infisical-relay?ref=v0.0.4"

  name_prefix       = "example"
  aws_region        = "us-east-1"
  primary_region    = "us-east-1"
  vpc_id            = "vpc-0123456789abcdef0"
  public_subnet_ids = ["subnet-0123456789abcdef0"]
  ami_id            = "ami-0123456789abcdef0" # Ubuntu 22.04 LTS

  relay_instances = {
    "example-relay-1" = { index = 1, az_index = 0 }
  }

  # Optional alarms
  enable_monitoring    = true
  enable_cpu_alarm     = true
  alarm_sns_topic_arns = ["arn:aws:sns:us-east-1:123456789012:alerts"]
}
```

## Network access

| Port | Purpose | Source |
| ---- | ------- | ------ |
| 8443/tcp | Platform-to-relay communication | `allowed_cidr_blocks` |
| 2222/tcp | SSH reverse tunnel from gateways | `allowed_cidr_blocks` |
| 22/tcp | Administrative SSH | `admin_ssh_cidr_blocks`, closed by default |

Ports 8443 and 2222 are the relay's service ports. Port 22 stays closed in both the security group and the host firewall (ufw) unless `admin_ssh_cidr_blocks` is set. When it is set, both layers allow port 22 only from those ranges. Entries must be IPv4 network addresses of `/8` or narrower.

The security group follows `admin_ssh_cidr_blocks` on every apply. The host firewall is configured at boot, so a change to `admin_ssh_cidr_blocks` reaches ufw only on instances launched after the change (see [Upgrading from v0.0.3](#upgrading-from-v003) for how to replace an instance). The module does not set an EC2 key pair; SSH login uses keys from the AMI or EC2 Instance Connect.

For shell access, use AWS Systems Manager Session Manager. With `enable_ssm_session_manager = true` (the default), the module attaches `AmazonSSMManagedInstanceCore` to the relay role. Access is governed by IAM through `ssm:StartSession`. Set `enable_ssm_session_manager = false` to opt out. Session Manager needs no inbound ports. It does need the SSM agent on the AMI (preinstalled on Canonical's Ubuntu 22.04 LTS AMIs) and outbound HTTPS, which the default egress rule allows.

## Instance metadata

The launch template requires IMDSv2 (`http_tokens = "required"`) with a hop limit of 1.

## Alarms

- `enable_monitoring` ships relay service logs to CloudWatch Logs and adds an alarm on service failures.
- `enable_cpu_alarm` adds one CloudWatch alarm per relay on `AWS/EC2` `CPUUtilization`, aggregated by Auto Scaling Group. It fires when average CPU stays at or above `cpu_alarm_threshold` (default 80%) for three consecutive 5-minute periods.

Both alarms notify `alarm_sns_topic_arns` on alarm and on recovery. The CPU alarm ARNs are available in the `cpu_alarm_arns` output, keyed by relay name.

## Inputs added in v0.0.4

| Name | Type | Default | Description |
| ---- | ---- | ------- | ----------- |
| `admin_ssh_cidr_blocks` | `list(string)` | `[]` | IPv4 CIDR blocks (`/8` or narrower) allowed to reach port 22. Empty keeps port 22 closed. |
| `enable_ssm_session_manager` | `bool` | `true` | Attach `AmazonSSMManagedInstanceCore` to the relay role. |
| `enable_cpu_alarm` | `bool` | `false` | Create a CPU alarm per relay Auto Scaling Group. |
| `cpu_alarm_threshold` | `number` | `80` | CPU percentage at or above which the alarm fires. |

## Upgrading from v0.0.3

**Breaking change: administrative SSH is now off by default.** Port 22 is closed unless you set `admin_ssh_cidr_blocks`. Use Session Manager, or set `admin_ssh_cidr_blocks` to the ranges that need SSH.

When the changes take effect:

- **On apply:** the security group and IAM changes, and CPU alarms if enabled. Instances may take a few minutes to register with Session Manager after the policy is attached.
- **On instance replacement:** IMDSv2 and the host firewall settings, which are part of the launch template. The module does not configure an instance refresh, so these apply to instances launched after the upgrade.

To roll a relay onto the new launch template, terminate its instance and let the Auto Scaling Group launch a replacement, or start an instance refresh on its Auto Scaling Group. Each relay runs a single instance, so the relay is unavailable while the replacement boots and re-associates its Elastic IP, typically a few minutes. The public IP does not change.
