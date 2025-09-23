#!/bin/bash
set -e

# Variables from Terraform template
RELAY_NAME="${relay_name}"
AWS_REGION="${region}"
PRIMARY_REGION="${primary_region}"
INFISICAL_DOMAIN="${infisical_domain}"
RELAY_AUTH_SECRET_PARAMETER="${relay_auth_secret_parameter}"
EIP_ALLOCATION_ID="${eip_allocation_id}"

# Log all output
exec > >(tee /var/log/relay-setup.log)
exec 2>&1

echo "========================================="
echo "Starting Infisical Relay setup..."
echo "Relay Name: $RELAY_NAME"
echo "AWS Region: $AWS_REGION"
echo "========================================="

# Update system packages
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required packages
echo "Installing required packages..."
apt-get install -y curl wget unzip jq awscli

# Create infisical user
echo "Creating infisical user..."
useradd --system --create-home --shell /bin/bash infisical

# Install Infisical CLI
echo "Installing Infisical CLI..."
curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | bash
apt-get update && apt-get install -y infisical

# Get instance metadata
echo "Retrieving instance metadata..."
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

echo "Instance ID: $INSTANCE_ID"
echo "Private IP: $PRIVATE_IP"

# Associate the pre-allocated EIP for this relay
echo "Associating EIP allocation ID: $EIP_ALLOCATION_ID to instance: $INSTANCE_ID"
aws ec2 associate-address \
  --instance-id $INSTANCE_ID \
  --allocation-id $EIP_ALLOCATION_ID \
  --region $AWS_REGION

# Wait a moment for association to complete
sleep 10

# Get the associated public IP
echo "Getting associated EIP..."
PUBLIC_IP=$(aws ec2 describe-addresses \
  --region $AWS_REGION \
  --allocation-ids $EIP_ALLOCATION_ID \
  --query 'Addresses[0].PublicIp' \
  --output text)

if [ "$PUBLIC_IP" = "None" ] || [ "$PUBLIC_IP" = "null" ] || [ -z "$PUBLIC_IP" ]; then
  echo "ERROR: Failed to associate or retrieve EIP"
  exit 1
fi

echo "Successfully associated EIP: $PUBLIC_IP"

# Retrieve relay auth secret from Parameter Store
echo "Retrieving relay auth secret from Parameter Store..."

INFISICAL_RELAY_AUTH_SECRET=$(aws ssm get-parameter \
  --name "$RELAY_AUTH_SECRET_PARAMETER" \
  --with-decryption \
  --region $PRIMARY_REGION \
  --query Parameter.Value \
  --output text)

if [ -z "$INFISICAL_RELAY_AUTH_SECRET" ]; then
  echo "ERROR: Failed to retrieve valid relay auth secret from Parameter Store"
  echo "Please update the SSM parameter $RELAY_AUTH_SECRET_PARAMETER with a real secret"
  exit 1
fi

echo "Retrieved relay auth secret from Parameter Store"

echo "Infisical Domain: $INFISICAL_DOMAIN"

# Configure firewall (ufw)
echo "Configuring firewall..."
ufw --force enable
ufw allow 22/tcp    # SSH access
ufw allow 8443/tcp  # Relay platform communication
ufw allow 2222/tcp  # SSH reverse tunnel

# Install and start instance relay using systemd method
echo "Installing Infisical Instance Relay as systemd service..."

# Set environment variable for instance relay
export INFISICAL_RELAY_AUTH_SECRET="$INFISICAL_RELAY_AUTH_SECRET"

# Install instance relay as systemd service
echo "Installing instance relay..."
sudo INFISICAL_RELAY_AUTH_SECRET="$INFISICAL_RELAY_AUTH_SECRET" infisical relay systemd install \
  --type=instance \
  --name "$RELAY_NAME" \
  --domain "$INFISICAL_DOMAIN" \
  --host "$PUBLIC_IP"

# Start the service (systemd install enables but doesn't start)
sudo systemctl start infisical-relay

# Wait a moment and check service status
sleep 5
if systemctl is-active --quiet infisical-relay.service; then
  echo "Infisical Relay service started successfully!"
  systemctl status infisical-relay.service --no-pager
else
  echo "Infisical Relay service failed to start"
  systemctl status infisical-relay.service --no-pager
  journalctl -u infisical-relay.service --no-pager -n 20
fi

echo "========================================="
echo "Infisical Relay setup completed!"
echo "Service status: $(systemctl is-active infisical-relay.service)"
echo "Public IP: $PUBLIC_IP"
echo "Relay Name: $RELAY_NAME"
echo "========================================="
