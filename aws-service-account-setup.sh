#!/bin/bash
# Enhanced AWS Security Hub Setup Script
# This script creates a service account role with specific read-only permissions

# Function to get AWS region
get_aws_region() {
    # Try environment variable first
    if [ -n "$AWS_REGION" ]; then
        echo "Using AWS_REGION from environment: $AWS_REGION"
        return 0
    fi
    
    # Try AWS CLI configuration
    AWS_REGION=$(aws configure get region 2>/dev/null)
    if [ -n "$AWS_REGION" ]; then
        echo "Using AWS region from CLI configuration: $AWS_REGION"
        return 0
    fi
    
    # If running interactively, prompt for region
    if [ -t 0 ]; then
        read -p "Enter the AWS Region (e.g., us-east-1): " AWS_REGION
        if [ -n "$AWS_REGION" ]; then
            return 0
        fi
    fi
    
    # Default to us-east-1 if nothing else works
    echo "No region specified. Using default: us-east-1"
    echo "You can set your region with: aws configure set region YOUR_REGION"
    echo "Or run with: AWS_REGION=your-region curl ... | bash"
    AWS_REGION="us-east-1"
}

# Get AWS region
get_aws_region

# Validate region is not empty
if [ -z "$AWS_REGION" ]; then
    echo "Error: AWS Region is required"
    echo "Set it with one of these methods:"
    echo "1. aws configure set region YOUR_REGION"
    echo "2. AWS_REGION=your-region curl ... | bash"
    echo "3. export AWS_REGION=your-region"
    exit 1
fi

# Automatically generate role name with timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
ROLE_NAME="SecurityHubAppRole-${TIMESTAMP}"

echo "Starting AWS Security Hub setup process..."
echo "Using auto-generated role name: $ROLE_NAME"
echo "Using AWS region: $AWS_REGION"

# Function to check for errors
check_error() {
    if [ $? -ne 0 ]; then
        echo "Error occurred in the last command"
        echo "Press any key to exit..."
        read -n 1 -s 2>/dev/null || sleep 2
        exit 1
    fi
}

# Trap any unexpected errors
trap 'echo "An unexpected error occurred."; echo "Press any key to exit..."; read -n 1 -s 2>/dev/null || sleep 2; exit 1' ERR

# Configure AWS CLI region
echo "Configuring AWS region to $AWS_REGION..."
aws configure set region "$AWS_REGION"
check_error

# Get AWS Account ID
echo "Getting AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
check_error
echo "AWS Account ID: $ACCOUNT_ID"

# Enable AWS Config if not already enabled
echo "Checking and enabling AWS Config..."
aws configservice describe-configuration-recorders 2>/dev/null || {
    echo "AWS Config not enabled. Setting up AWS Config..."

    # Create service-linked role for AWS Config
    echo "Creating AWS Config service-linked role..."
    aws iam create-service-linked-role --aws-service-name config.amazonaws.com 2>/dev/null || echo "Config service role may already exist"

    # Create S3 bucket for AWS Config
    CONFIG_BUCKET="config-bucket-$ACCOUNT_ID-${TIMESTAMP}"
    echo "Creating S3 bucket: $CONFIG_BUCKET"
    aws s3 mb "s3://$CONFIG_BUCKET"
    check_error

    # Configure Config recording
    echo "Setting up AWS Config recorder..."
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
    echo "Setting up AWS Config delivery channel..."
    aws configservice put-delivery-channel --delivery-channel "{
        \"name\": \"default\",
        \"s3BucketName\": \"$CONFIG_BUCKET\",
        \"configSnapshotDeliveryProperties\": {
            \"deliveryFrequency\": \"Six_Hours\"
        }
    }"
    check_error

    # Start configuration recorder
    echo "Starting AWS Config recorder..."
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
echo "Getting current user ARN..."
USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
check_error
echo "Current user ARN: $USER_ARN"

# Create custom policy with specific permissions
echo "Creating custom IAM policy with required permissions..."
POLICY_NAME="SahlSecurityReadOnlyPolicy-${TIMESTAMP}"

# Create the policy document
cat > /tmp/policy.json << 'EOF'
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
echo "Creating IAM policy: $POLICY_NAME"
aws iam create-policy --policy-name "$POLICY_NAME" --policy-document file:///tmp/policy.json
check_error

# Clean up policy file
rm -f /tmp/policy.json

# Create IAM Role
echo "Creating IAM Role: $ROLE_NAME"
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"$USER_ARN\"},\"Action\":\"sts:AssumeRole\"}]}"
check_error

# Attach the custom policy
echo "Attaching custom policy to role..."
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"
check_error

# Output role ARN
echo "Getting role ARN..."
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)
check_error

# Save details to file
echo ""
echo "=========================="
echo "Setup completed successfully!"
echo "=========================="
echo "Role ARN: $ROLE_ARN"
echo "Please provide this Role ARN and your AWS access key and secret key to the Sahl application."

# Create details file
DETAILS_FILE="$HOME/aws-security-hub-details.txt"
cat > "$DETAILS_FILE" << EOF
Service Account Details
------------------------
Role Name: $ROLE_NAME
Role ARN: $ROLE_ARN
Policy Name: $POLICY_NAME
AWS Account ID: $ACCOUNT_ID
Region: $AWS_REGION
Created on: $(date)

Permissions granted:
- IAM: ListUsers, ListAccessKeys, ListMFADevices, GetAccountSummary
- S3: ListBuckets, GetBucketPolicyStatus, GetBucketEncryption
- CloudTrail: DescribeTrails, GetEventSelectors
- EC2: DescribeSecurityGroups
- Config: GetComplianceSummaryByConfigRule
- Security Hub: GetFindings
EOF

echo ""
echo "Permissions granted:"
echo "- IAM: ListUsers, ListAccessKeys, ListMFADevices, GetAccountSummary"
echo "- S3: ListBuckets, GetBucketPolicyStatus, GetBucketEncryption"
echo "- CloudTrail: DescribeTrails, GetEventSelectors"
echo "- EC2: DescribeSecurityGroups"
echo "- Config: GetComplianceSummaryByConfigRule"
echo "- Security Hub: GetFindings"
echo ""
echo "Details have been saved to: $DETAILS_FILE"
echo "KEEP THESE DETAILS SECURE!"
echo ""
echo "You can now use the Role ARN with your Sahl application."

# Only pause if running interactively
if [ -t 0 ]; then
    echo "Press any key to exit..."
    read -n 1 -s
fi