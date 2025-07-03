#!/bin/bash
# Simple AWS Setup - No Interactive Input Required
# Usage: bash aws-simple-setup.sh

echo "AWS Security Hub Setup - Simple Mode"
echo "====================================="
echo ""
echo "This script will set up AWS Security Hub using your AWS Account ID: 040745305102"
echo "and region: eu-north-1 (based on your previous inputs)"
echo ""
echo "If you need different values, please use:"
echo "curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-service-account-setup.sh | bash -s YOUR_ACCOUNT_ID YOUR_REGION"
echo ""

read -p "Press Enter to continue with Account ID 040745305102 and region eu-north-1, or Ctrl+C to cancel..."

echo ""
echo "Starting setup..."

# Download and run the main script with the known values
curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-service-account-setup.sh | bash -s "040745305102" "eu-north-1"
