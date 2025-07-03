#!/bin/bash
# AWS Setup Wrapper Script
# This script prompts for Account ID and Region, then runs the main setup script

echo "AWS Security Hub Setup - Interactive Mode"
echo "=========================================="
echo ""

# Prompt for Account ID
while true; do
    read -p "Enter your AWS Account ID (12 digits): " ACCOUNT_ID
    if [[ $ACCOUNT_ID =~ ^[0-9]{12}$ ]]; then
        break
    else
        echo "ERROR: AWS Account ID must be exactly 12 digits. Please try again."
    fi
done

# Prompt for Region
echo ""
echo "Common AWS Regions:"
echo "  us-east-1      (US East - N. Virginia)"
echo "  us-west-2      (US West - Oregon)"
echo "  eu-west-1      (Europe - Ireland)"
echo "  eu-north-1     (Europe - Stockholm)"
echo "  ap-southeast-1 (Asia Pacific - Singapore)"
echo ""

while true; do
    read -p "Enter the AWS Region: " AWS_REGION
    if [[ -n "$AWS_REGION" ]]; then
        break
    else
        echo "ERROR: AWS Region cannot be empty. Please try again."
    fi
done

echo ""
echo "Running setup with:"
echo "Account ID: $ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo ""

# Download and run the main script
curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-service-account-setup.sh | bash -s "$ACCOUNT_ID" "$AWS_REGION"
