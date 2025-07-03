#!/bin/bash
# AWS Security Hub Setup Script with Required Permissions
# Creates an IAM role with specific read-only permissions

# Prompt for required variables
read -p "Enter your AWS Account ID: " ACCOUNT_ID
read -p "Enter the AWS Region (e.g., us-east-1): " AWS_REGION

# Automatically generate role name with timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
ROLE_NAME="SecurityHubReadOnlyRole-${TIMESTAMP}"
POLICY_NAME="SahlSecurityReadOnlyPolicy-${TIMESTAMP}"

echo "Starting AWS Security Hub setup process..."
echo "Using auto-generated role name: $ROLE_NAME"
echo "Using policy name: $POLICY_NAME"

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

# Get current user's ARN for the trust policy
echo "Getting current user ARN..."
USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
check_error
echo "Current user ARN: $USER_ARN"

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

# Create custom IAM policy with the required permissions
echo "Creating custom IAM policy with required permissions..."
aws iam create-policy --policy-name "$POLICY_NAME" --policy-document '{
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
}' --description "Read-only permissions for Sahl security monitoring application"
check_error

# Get the Policy ARN
POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"

# Create IAM Role with trust policy allowing the current user to assume it
echo "Creating IAM Role: $ROLE_NAME"
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Effect\": \"Allow\",
            \"Principal\": {
                \"AWS\": \"$USER_ARN\"
            },
            \"Action\": \"sts:AssumeRole\"
        }
    ]
}" --description "Read-only role for Sahl security monitoring application"
check_error

# Attach the custom policy to the role
echo "Attaching custom policy to role..."
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
check_error

# Get the Role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)
check_error

# Save details to file
echo "Setup completed successfully!"
echo "Role ARN: $ROLE_ARN"
echo ""
echo "Service Account Details" > ~/aws-security-hub-details.txt
echo "------------------------" >> ~/aws-security-hub-details.txt
echo "Role Name: $ROLE_NAME" >> ~/aws-security-hub-details.txt
echo "Role ARN: $ROLE_ARN" >> ~/aws-security-hub-details.txt
echo "Policy Name: $POLICY_NAME" >> ~/aws-security-hub-details.txt
echo "Policy ARN: $POLICY_ARN" >> ~/aws-security-hub-details.txt
echo "AWS Account ID: $ACCOUNT_ID" >> ~/aws-security-hub-details.txt
echo "Region: $AWS_REGION" >> ~/aws-security-hub-details.txt
echo "Created on: $(date)" >> ~/aws-security-hub-details.txt
echo "" >> ~/aws-security-hub-details.txt
echo "Permissions granted:" >> ~/aws-security-hub-details.txt
echo "- IAM: ListUsers, ListAccessKeys, ListMFADevices, GetAccountSummary" >> ~/aws-security-hub-details.txt
echo "- S3: ListBuckets, GetBucketPolicyStatus, GetBucketEncryption" >> ~/aws-security-hub-details.txt
echo "- CloudTrail: DescribeTrails, GetEventSelectors" >> ~/aws-security-hub-details.txt
echo "- EC2: DescribeSecurityGroups" >> ~/aws-security-hub-details.txt
echo "- Config: GetComplianceSummaryByConfigRule" >> ~/aws-security-hub-details.txt
echo "- Security Hub: GetFindings" >> ~/aws-security-hub-details.txt
echo "" >> ~/aws-security-hub-details.txt
echo "Usage Instructions:" >> ~/aws-security-hub-details.txt
echo "1. Provide the Role ARN to your Sahl application" >> ~/aws-security-hub-details.txt
echo "2. Provide your AWS access key and secret key" >> ~/aws-security-hub-details.txt
echo "3. The application will assume this role to access AWS resources" >> ~/aws-security-hub-details.txt

echo "Permissions granted:"
echo "- IAM: ListUsers, ListAccessKeys, ListMFADevices, GetAccountSummary"
echo "- S3: ListBuckets, GetBucketPolicyStatus, GetBucketEncryption"
echo "- CloudTrail: DescribeTrails, GetEventSelectors"
echo "- EC2: DescribeSecurityGroups"
echo "- Config: GetComplianceSummaryByConfigRule"
echo "- Security Hub: GetFindings"
echo ""
echo "Details have been saved to ~/aws-security-hub-details.txt"
echo "KEEP THESE DETAILS SECURE!"
echo ""
echo "To use this role:"
echo "1. Provide the Role ARN: $ROLE_ARN"
echo "2. Provide your AWS credentials to the Sahl application"
echo "3. The application will assume this role to access your AWS resources"
echo ""
echo "Press any key to exit..."
read -n 1