#!/bin/bash
# AWS Security Hub Setup Script - Simplified Version
# Creates an IAM role with specific read-only permissions

# Fix AWS config first
echo "Fixing AWS configuration..."
rm -f ~/.aws/config ~/.aws/credentials
mkdir -p ~/.aws

# Prompt for required variables
read -p "Enter your AWS Account ID: " ACCOUNT_ID
read -p "Enter the AWS Region (e.g., us-east-1): " AWS_REGION

# Create clean config file
cat > ~/.aws/config << EOF
[default]
region = $AWS_REGION
output = json
EOF

# Automatically generate role name with timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
ROLE_NAME="SecurityHubReadOnlyRole-${TIMESTAMP}"
POLICY_NAME="SahlSecurityReadOnlyPolicy-${TIMESTAMP}"

echo "Starting AWS Security Hub setup process..."
echo "Using auto-generated role name: $ROLE_NAME"
echo "Using policy name: $POLICY_NAME"

# Get current user's ARN for the trust policy
echo "Getting current user ARN..."
USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
echo "Current user ARN: $USER_ARN"

# Enable Security Hub
echo "Enabling AWS Security Hub..."
aws securityhub enable-security-hub 2>/dev/null || echo "Security Hub may already be enabled"

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

# Attach the custom policy to the role
echo "Attaching custom policy to role..."
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"

# Get the Role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)

# Save details to file
echo "=================================================="
echo "Setup completed successfully!"
echo "=================================================="
echo "Role ARN: $ROLE_ARN"
echo ""

# Save to file
echo "Service Account Details" > ~/aws-security-hub-details.txt
echo "------------------------" >> ~/aws-security-hub-details.txt
echo "Role Name: $ROLE_NAME" >> ~/aws-security-hub-details.txt
echo "Role ARN: $ROLE_ARN" >> ~/aws-security-hub-details.txt
echo "Policy Name: $POLICY_NAME" >> ~/aws-security-hub-details.txt
echo "Policy ARN: $POLICY_ARN" >> ~/aws-security-hub-details.txt
echo "AWS Account ID: $ACCOUNT_ID" >> ~/aws-security-hub-details.txt
echo "Region: $AWS_REGION" >> ~/aws-security-hub-details.txt
echo "Created on: $(date)" >> ~/aws-security-hub-details.txt

echo "Permissions granted:"
echo "- IAM: ListUsers, ListAccessKeys, ListMFADevices, GetAccountSummary"
echo "- S3: ListBuckets, GetBucketPolicyStatus, GetBucketEncryption"
echo "- CloudTrail: DescribeTrails, GetEventSelectors"
echo "- EC2: DescribeSecurityGroups"
echo "- Config: GetComplianceSummaryByConfigRule"
echo "- Security Hub: GetFindings"
echo ""
echo "Details saved to ~/aws-security-hub-details.txt"
echo ""
echo "IMPORTANT: Copy this Role ARN for your Sahl application:"
echo "$ROLE_ARN"
echo ""
