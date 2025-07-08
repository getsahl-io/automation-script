#!/bin/bash
# AWS Security Hub Setup Script - Access Keys Version
# Creates an IAM user with access keys and specific read-only permissions

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

# Automatically generate user name with timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
USER_NAME="SahlSecurityUser-${TIMESTAMP}"
POLICY_NAME="SahlSecurityReadOnlyPolicy-${TIMESTAMP}"

echo "Starting AWS Security Hub setup process..."
echo "Using auto-generated user name: $USER_NAME"
echo "Using policy name: $POLICY_NAME"

# Enable Security Hub
echo "Enabling AWS Security Hub..."
aws securityhub enable-security-hub 2>/dev/null || echo "Security Hub may already be enabled"

# Create custom IAM policy with the required permissions (corrected)
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
                "s3:ListAllMyBuckets",
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

# Create IAM User
echo "Creating IAM User: $USER_NAME"
aws iam create-user --user-name "$USER_NAME" --path "/" --tags Key=Purpose,Value=SahlSecurityMonitoring Key=CreatedBy,Value=SahlScript

# Attach the custom policy to the user
echo "Attaching custom policy to user..."
aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$POLICY_ARN"

# Create access keys for the user
echo "Creating access keys..."
ACCESS_KEY_OUTPUT=$(aws iam create-access-key --user-name "$USER_NAME")

# Extract access key ID and secret access key
ACCESS_KEY_ID=$(echo "$ACCESS_KEY_OUTPUT" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_OUTPUT" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)

# Get the User ARN
USER_ARN=$(aws iam get-user --user-name "$USER_NAME" --query User.Arn --output text)

# Verify the access keys work by testing them
echo "Testing access keys..."
export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$AWS_REGION"

# Test the credentials with a simple API call
TEST_RESULT=$(aws sts get-caller-identity 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "✅ Access keys verified successfully!"
    TEST_ACCOUNT_ID=$(echo "$TEST_RESULT" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    TEST_USER_ID=$(echo "$TEST_RESULT" | grep -o '"UserId": "[^"]*"' | cut -d'"' -f4)
    echo "Verified Account ID: $TEST_ACCOUNT_ID"
    echo "User ID: $TEST_USER_ID"
else
    echo "⚠️  Warning: Could not verify access keys immediately. They may need a few seconds to propagate."
fi

# Save details to JSON file
echo "=================================================="
echo "Setup completed successfully!"
echo "=================================================="
echo "User ARN: $USER_ARN"
echo "Access Key ID: $ACCESS_KEY_ID"
echo "Secret Access Key: [HIDDEN FOR SECURITY]"
echo ""

# Create JSON file with service account details
cat > ~/aws-service-account-credentials.json << EOF
{
  "userName": "$USER_NAME",
  "userArn": "$USER_ARN",
  "policyName": "$POLICY_NAME",
  "policyArn": "$POLICY_ARN",
  "accountId": "$ACCOUNT_ID",
  "region": "$AWS_REGION",
  "accessKeyId": "$ACCESS_KEY_ID",
  "secretAccessKey": "$SECRET_ACCESS_KEY",
  "createdOn": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "permissions": [
    "iam:ListUsers",
    "iam:ListAccessKeys",
    "iam:ListMFADevices",
    "iam:GetAccountSummary",
    "s3:ListAllMyBuckets",
    "s3:GetBucketPolicyStatus",
    "s3:GetBucketEncryption",
    "cloudtrail:DescribeTrails",
    "cloudtrail:GetEventSelectors",
    "ec2:DescribeSecurityGroups",
    "config:GetComplianceSummaryByConfigRule",
    "securityhub:GetFindings"
  ],
  "description": "AWS Security Hub service account credentials for Sahl security monitoring application"
}
EOF

echo "Permissions granted:"
echo "- IAM: ListUsers, ListAccessKeys, ListMFADevices, GetAccountSummary"
echo "- S3: ListAllMyBuckets, GetBucketPolicyStatus, GetBucketEncryption"
echo "- CloudTrail: DescribeTrails, GetEventSelectors"
echo "- EC2: DescribeSecurityGroups"
echo "- Config: GetComplianceSummaryByConfigRule"
echo "- Security Hub: GetFindings"
echo ""
echo "🔐 SECURITY IMPORTANT:"
echo "- Access keys are saved in the JSON file"
echo "- Keep this file secure and do not share it publicly"
echo "- Consider rotating these keys regularly (every 90 days)"
echo "- You can delete this user from AWS IAM console when no longer needed"
echo ""
echo "Credentials saved to ~/aws-service-account-credentials.json"
echo ""
echo "IMPORTANT: Download the JSON file using Cloud Shell's download feature:"
echo "1. Use the three-dot menu (⋮) in Cloud Shell"
echo "2. Select 'Download file'"
echo "3. Enter: aws-service-account-credentials.json"
echo ""
echo "Access Key ID: $ACCESS_KEY_ID"
echo "User ARN: $USER_ARN"
echo ""
echo "⚠️  SECURITY REMINDER:"
echo "The JSON file contains sensitive access keys. Store it securely!"
echo ""
echo "🔧 TESTING PERMISSIONS:"
echo "You can now test these credentials in the Sahl application."
echo "If any permissions are still missing, check the AWS IAM console to ensure"
echo "the policy was attached correctly to the user: $USER_NAME"
