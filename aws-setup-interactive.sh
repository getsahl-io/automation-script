#!/bin/bash
# AWS Setup Wrapper Script
# This script prompts for Account ID and Region, then runs the main setup script

echo "AWS Security Hub Setup - Interactive Mode"
echo "=========================================="
echo ""
echo "This script will help you set up AWS Security Hub for Sahl monitoring."
echo "You'll need your 12-digit AWS Account ID and preferred AWS region."
echo ""

# Prompt for Account ID
while true; do
    read -p "Enter your AWS Account ID (12 digits): " ACCOUNT_ID
    # Remove any whitespace
    ACCOUNT_ID=$(echo "$ACCOUNT_ID" | tr -d '[:space:]')
    # Check if it's exactly 12 digits
    if [[ ${#ACCOUNT_ID} -eq 12 ]] && [[ $ACCOUNT_ID =~ ^[0-9]+$ ]]; then
        echo "Valid Account ID: $ACCOUNT_ID"
        break
    else
        echo "ERROR: AWS Account ID must be exactly 12 digits (you entered: '$ACCOUNT_ID' with ${#ACCOUNT_ID} characters). Please try again."
        echo "Example: 123456789012"
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
    # Remove any whitespace
    AWS_REGION=$(echo "$AWS_REGION" | tr -d '[:space:]')
    if [[ -n "$AWS_REGION" ]] && [[ ${#AWS_REGION} -ge 8 ]]; then
        echo "Using region: $AWS_REGION"
        break
    else
        echo "ERROR: AWS Region cannot be empty and should be at least 8 characters (you entered: '$AWS_REGION'). Please try again."
        echo "Example: us-east-1 or eu-north-1"
    fi
done

echo ""
echo "Running setup with:"
echo "Account ID: $ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo ""

# Download and run the main script
curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-service-account-setup.sh | bash -s "$ACCOUNT_ID" "$AWS_REGION"
