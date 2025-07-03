#!/bin/bash
# Enhanced AWS Security Hub Setup Script
# This script creates a service account role with specific read-only permissions

# Prompt for required variables
read -p "Enter the AWS Region (e.g., us-east-1): " AWS_REGION

# Automatically generate role name with timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
ROLE_NAME="SecurityHubAppRole-${TIMESTAMP}"

echo "Starting AWS Security Hub setup process..."
echo "Using auto-generated role name: $ROLE_NAME"

# Function to check for errors
check_error() {
    if [ $? -ne 0 ]; then
        echo "Error occurred in the last command"
        echo "Press any key to exit..."
        read -n 1
        exit 1
    fi
}

# Trap any unexpected errors
trap 'echo "An unexpected error occurred."; echo "Press any key to exit..."; read -n 1; exit 1' ERR

# Configure AWS CLI region
echo "Configuring AWS region to $AWS_REGION..."
aws configure set region "$AWS_REGION"
check_error

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
check_error

# Enable AWS Config if not already enabled
echo "Checking and enabling AWS Config..."
aws configservice describe-configuration-recorders 2>/dev/null || {
    echo "AWS Config not enabled. Setting up AWS Config..."

    # Create service-linked role for AWS Config
    aws iam create-service-linked-role --aws-service-name config.amazonaws.com 2>/dev/null || echo "Config service role may already exist"

    # Create S3 bucket for AWS Config
    CONFIG_BUCKET="config-bucket-$ACCOUNT_ID-${TIMESTAMP}"
    aws s3 mb "s3://$CONFIG_BUCKET"
    check_error

    # Configure Config recording
    aws configservice put-configuration-recorder --configuration-recorder "{
        \"name\": \"default\",
        \"roleARN\": \"arn:aws:iam::$ACCOUNT_ID:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig\",
        \"recordingGroup\": {
            \"allSupported\": true,
            \"includeGlobalResourceTypes\": true
        }
    }"
    check_error

    # Set up delivery channel
    aws configservice put-delivery-channel --delivery-channel "{
        \"name\": \"default\",
        \"s3BucketName\": \"$CONFIG_BUCKET\",
        \"configSnapshotDeliveryProperties\": {
            \"deliveryFrequency\": \"Six_Hours\"
        }
    }"
    check_error

    # Start configuration recorder
    aws configservice start-configuration-recorder --configuration-recorder-name default
    check_error
}

# Enable Security Hub
echo "Enabling AWS Security Hub..."
aws securityhub enable-security-hub 2>/dev/null || echo "Security Hub may already be enabled"

# Enable AWS Foundational Security Best Practices standard
echo "Enabling AWS Foundational Security Best Practices standard..."
aws securityhub enable-security-standard --standards-arn "arn:aws:securityhub:$AWS_REGION:$ACCOUNT_ID:standard/aws-foundational-security-best-practices/v/1.0.0" 2>/dev/null || echo "Standard may already be enabled"

# Get current user's ARN
USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
check_error

# Create custom policy with specific permissions
echo "Creating custom IAM policy with required permissions..."
POLICY_NAME="SahlSecurityReadOnlyPolicy-${TIMESTAMP}"

# Create the policy document
cat > policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:ListUsers",
                "iam:ListAccessKeys",
                "iam:ListMFADevices",
                "iam:GetAccountSummary",
                "s3:ListBuckets",
                "s3:GetBucketPolicyStatus",
                "s3:GetBucketEncryption",
                "cloudtrail:DescribeTrails",
                "cloudtrail:GetEventSelectors",
                "ec2:DescribeSecurityGroups",
                "config:GetComplianceSummaryByConfigRule",
                "securityhub:GetFindings"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create the policy
aws iam create-policy --policy-name "$POLICY_NAME" --policy-document file://policy.json
check_error

# Clean up policy file
rm policy.json

# Create IAM Role
echo "Creating IAM Role: $ROLE_NAME"
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"$USER_ARN\"},\"Action\":\"sts:AssumeRole\"}]}"
check_error

# Attach the custom policy
echo "Attaching custom policy to role"
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"
check_error

# Output role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)
check_error

# Save details to file
echo "Setup completed successfully!"
echo "Role ARN: $ROLE_ARN"
echo "Please provide this Role ARN and your AWS access key and secret key to the Sahl application."
echo "Service Account Details" > ~/aws-security-hub-details.txt
echo "------------------------" >> ~/aws-security-hub-details.txt
echo "Role Name: $ROLE_NAME" >> ~/aws-security-hub-details.txt
echo "Role ARN: $ROLE_ARN" >> ~/aws-security-hub-details.txt
echo "Policy Name: $POLICY_NAME" >> ~/aws-security-hub-details.txt
echo "AWS Account ID: $ACCOUNT_ID" >> ~/aws-security-hub-details.txt
echo "Region: $AWS_REGION" >> ~/aws-security-hub-details.txt
echo "Created on: $(date)" >> ~/aws-security-hub-details.txt

echo ""
echo "Permissions granted:"
echo "- IAM: ListUsers, ListAccessKeys, ListMFADevices, GetAccountSummary"
echo "- S3: ListBuckets, GetBucketPolicyStatus, GetBucketEncryption"
echo "- CloudTrail: DescribeTrails, GetEventSelectors"
echo "- EC2: DescribeSecurityGroups"
echo "- Config: GetComplianceSummaryByConfigRule"
echo "- Security Hub: GetFindings"
echo ""
echo "Details have been saved to ~/aws-security-hub-details.txt. KEEP THESE SECURE!"
echo "Press any key to exit..."
read -n 1