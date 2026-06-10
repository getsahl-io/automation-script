#!/bin/bash
# AWS Service Account Setup Script
# Creates an IAM user with access keys and read-only permissions for Sahl

set -e

echo "=================================================="
echo "  Sahl AWS Service Account Setup"
echo "=================================================="
echo ""

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

echo ""
echo "Using auto-generated user name: $USER_NAME"
echo "Using policy name: $POLICY_NAME"
echo ""

# Enable Security Hub
echo "Enabling AWS Security Hub..."
aws securityhub enable-security-hub 2>/dev/null || echo "Security Hub may already be enabled"

# Enable AWS Config (required for Asset Register integration)
echo "Enabling AWS Config..."
aws configservice put-configuration-recorder \
  --configuration-recorder name=default,roleARN=arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig \
  2>/dev/null || echo "Config recorder may already be set up or requires manual setup"

# Create custom IAM policy with all required permissions
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
        "iam:GetAccountSummary"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListAllMyBuckets",
        "s3:GetBucketPolicyStatus",
        "s3:GetBucketEncryption"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudtrail:DescribeTrails",
        "cloudtrail:GetEventSelectors"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeSecurityGroups"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "config:GetComplianceSummaryByConfigRule",
        "config:ListDiscoveredResources",
        "config:BatchGetResourceConfig",
        "config:DescribeConfigurationRecorders",
        "config:DescribeConfigurationRecorderStatus"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "securityhub:GetFindings"
      ],
      "Resource": "*"
    }
  ]
}' --description "Read-only permissions for Sahl security monitoring and asset register"

# Get the Policy ARN
POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"

# Create IAM User
echo "Creating IAM User: $USER_NAME"
aws iam create-user \
  --user-name "$USER_NAME" \
  --path "/" \
  --tags Key=Purpose,Value=SahlSecurityMonitoring Key=CreatedBy,Value=SahlScript

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

# Verify the access keys work
echo ""
echo "Testing access keys..."
export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$AWS_REGION"

TEST_RESULT=$(aws sts get-caller-identity 2>/dev/null)
if [ $? -eq 0 ]; then
  echo "✅ Access keys verified successfully!"
  TEST_ACCOUNT_ID=$(echo "$TEST_RESULT" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
  echo "   Verified Account ID: $TEST_ACCOUNT_ID"
else
  echo "⚠️  Warning: Could not verify access keys immediately. They may need a few seconds to propagate."
fi

# Create JSON credentials file
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
    "config:ListDiscoveredResources",
    "config:BatchGetResourceConfig",
    "config:DescribeConfigurationRecorders",
    "config:DescribeConfigurationRecorderStatus",
    "securityhub:GetFindings"
  ],
  "description": "Sahl service account credentials for security monitoring and asset register"
}
EOF

echo ""
echo "=================================================="
echo "  Setup completed successfully!"
echo "=================================================="
echo ""
echo "User ARN:      $USER_ARN"
echo "Access Key ID: $ACCESS_KEY_ID"
echo "Secret Key:    [HIDDEN — see credentials file]"
echo ""
echo "Permissions granted:"
echo "  IAM        → ListUsers, ListAccessKeys, ListMFADevices, GetAccountSummary"
echo "  S3         → ListAllMyBuckets, GetBucketPolicyStatus, GetBucketEncryption"
echo "  CloudTrail → DescribeTrails, GetEventSelectors"
echo "  EC2        → DescribeSecurityGroups"
echo "  Config     → GetComplianceSummaryByConfigRule, ListDiscoveredResources,"
echo "               BatchGetResourceConfig, DescribeConfigurationRecorders,"
echo "               DescribeConfigurationRecorderStatus"
echo "  SecurityHub→ GetFindings"
echo ""
echo "🔐 SECURITY REMINDER:"
echo "  - Credentials saved to ~/aws-service-account-credentials.json"
echo "  - Keep this file secure — do not share or commit it"
echo "  - Rotate keys every 90 days via AWS IAM Console"
echo "  - Delete this user when no longer needed"
echo ""
echo "📥 DOWNLOAD CREDENTIALS (Cloud Shell):"
echo "  1. Click the three-dot menu (⋮) in Cloud Shell"
echo "  2. Select 'Download file'"
echo "  3. Enter: aws-service-account-credentials.json"
echo ""
echo "🔧 NEXT STEPS:"
echo "  1. Download the credentials file above"
echo "  2. Paste the Access Key ID and Secret Key into Sahl → Integrations → AWS"
echo "  3. If the Assets tab shows 'Config not enabled', enable AWS Config in your"
echo "     AWS Console → Config → Get started"
echo ""
