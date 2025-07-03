#!/bin/bash
# AWS Security Hub Setup Script with Required Permissions
# Creates an IAM role with specific read-only permissions

# Pre-flight checks
echo "Performing pre-flight checks..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI is not installed"
    echo "Please install AWS CLI first: https://aws.amazon.com/cli/"
    echo "Press any key to exit..."
    read -n 1
    exit 1
fi

# Check AWS CLI version
AWS_VERSION=$(aws --version 2>&1)
echo "Found AWS CLI: $AWS_VERSION"

# Get Account ID and Region from command line arguments or prompt
if [ -n "$1" ] && [ -n "$2" ]; then
    # Arguments provided via command line
    ACCOUNT_ID="$1"
    AWS_REGION="$2"
    echo "Using provided Account ID: $ACCOUNT_ID"
    echo "Using provided Region: $AWS_REGION"
elif [ -t 0 ]; then
    # Interactive mode - terminal is available
    read -p "Enter your AWS Account ID: " ACCOUNT_ID
    read -p "Enter the AWS Region (e.g., us-east-1): " AWS_REGION
else
    # Non-interactive mode (piped input) - show usage
    echo ""
    echo "Usage for non-interactive mode:"
    echo "curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-service-account-setup.sh | bash -s ACCOUNT_ID REGION"
    echo ""
    echo "Example:"
    echo "curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-service-account-setup.sh | bash -s 123456789012 us-east-1"
    echo ""
    echo "Or download and run interactively:"
    echo "curl -o aws-setup.sh https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-service-account-setup.sh"
    echo "chmod +x aws-setup.sh"
    echo "./aws-setup.sh"
    echo ""
    echo "Press any key to exit..."
    read -n 1 2>/dev/null || true
    exit 1
fi

# Validate inputs
if [[ ! $ACCOUNT_ID =~ ^[0-9]{12}$ ]]; then
    echo "ERROR: AWS Account ID must be exactly 12 digits"
    echo "Press any key to exit..."
    read -n 1
    exit 1
fi

if [[ -z "$AWS_REGION" ]]; then
    echo "ERROR: AWS Region cannot be empty"
    echo "Press any key to exit..."
    read -n 1
    exit 1
fi

# Automatically generate role name with timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
ROLE_NAME="SecurityHubReadOnlyRole-${TIMESTAMP}"
POLICY_NAME="SahlSecurityReadOnlyPolicy-${TIMESTAMP}"

echo "Starting AWS Security Hub setup process..."
echo "Using auto-generated role name: $ROLE_NAME"
echo "Using policy name: $POLICY_NAME"
echo "=================================================="

# Function to check for errors
check_error() {
    if [ $? -ne 0 ]; then
        echo "Error occurred in the last command"
        echo "Press any key to exit..."
        read -n 1
        exit 1
    fi
}

# Function to validate AWS credentials
validate_credentials() {
    echo "Validating AWS credentials..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        echo "ERROR: AWS CLI is not installed"
        echo "Please install AWS CLI first"
        echo "Press any key to exit..."
        read -n 1
        exit 1
    fi
    
    # Try to get caller identity
    aws sts get-caller-identity --output table 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: AWS credentials not configured or invalid"
        echo ""
        echo "To fix this issue:"
        echo "1. Run './fix-aws-config.sh' to reset your AWS config (if config is corrupted)"
        echo "2. Run 'aws configure' to set up your credentials"
        echo "3. Provide your AWS Access Key ID and Secret Access Key"
        echo "4. See TROUBLESHOOTING.md for detailed help"
        echo ""
        echo "Press any key to exit..."
        read -n 1
        exit 1
    fi
}

# Trap any unexpected errors
trap 'echo "An unexpected error occurred."; echo "Press any key to exit..."; read -n 1; exit 1' ERR

# Validate AWS credentials first
validate_credentials

# Configure AWS CLI region
echo "Configuring AWS region to $AWS_REGION..."

# Ensure AWS config directory exists
mkdir -p ~/.aws

# Check if config file exists and is readable
if [ ! -f ~/.aws/config ] || ! grep -q "^\[default\]" ~/.aws/config 2>/dev/null; then
    echo "Creating new AWS config file..."
    cat > ~/.aws/config << EOF
[default]
region = $AWS_REGION
output = json
EOF
else
    # Update existing config file
    aws configure set region "$AWS_REGION"
fi

# Verify the configuration worked
aws configure get region &>/dev/null
check_error

# Get current user's ARN for the trust policy
echo "Getting current user ARN..."
USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
check_error
echo "Current user ARN: $USER_ARN"

# Enable AWS Config if not already enabled
echo "Checking and enabling AWS Config..."
CONFIG_RECORDERS=$(aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[0].name' --output text 2>/dev/null)
if [ "$CONFIG_RECORDERS" = "None" ] || [ -z "$CONFIG_RECORDERS" ]; then
    echo "AWS Config not enabled. Setting up AWS Config..."

    # Create service-linked role for AWS Config
    aws iam create-service-linked-role --aws-service-name config.amazonaws.com 2>/dev/null || echo "Config service role may already exist"

    # Create S3 bucket for AWS Config with proper naming
    CONFIG_BUCKET="aws-config-bucket-$ACCOUNT_ID-$(echo $AWS_REGION | tr '-' '')-${TIMESTAMP}"
    echo "Creating S3 bucket: $CONFIG_BUCKET"
    aws s3 mb "s3://$CONFIG_BUCKET" --region "$AWS_REGION"
    check_error

    # Wait a moment for bucket to be available
    sleep 5

    # Configure Config recording
    echo "Setting up configuration recorder..."
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
    echo "Setting up delivery channel..."
    aws configservice put-delivery-channel --delivery-channel "{
        \"name\": \"default\",
        \"s3BucketName\": \"$CONFIG_BUCKET\",
        \"configSnapshotDeliveryProperties\": {
            \"deliveryFrequency\": \"Six_Hours\"
        }
    }"
    check_error

    # Start configuration recorder
    echo "Starting configuration recorder..."
    aws configservice start-configuration-recorder --configuration-recorder-name default
    check_error
    
    echo "AWS Config setup completed."
else
    echo "AWS Config is already enabled with recorder: $CONFIG_RECORDERS"
fi

# Enable Security Hub
echo "Enabling AWS Security Hub..."
SECURITYHUB_STATUS=$(aws securityhub describe-hub --query 'HubArn' --output text 2>/dev/null)
if [ "$SECURITYHUB_STATUS" = "None" ] || [ -z "$SECURITYHUB_STATUS" ]; then
    aws securityhub enable-security-hub
    check_error
    echo "AWS Security Hub enabled successfully."
else
    echo "AWS Security Hub is already enabled."
fi

# Enable AWS Foundational Security Best Practices standard
echo "Enabling AWS Foundational Security Best Practices standard..."
STANDARD_ARN="arn:aws:securityhub:$AWS_REGION::standard/aws-foundational-security-best-practices/v/1.0.0"
aws securityhub enable-security-standard --standards-arn "$STANDARD_ARN" 2>/dev/null || echo "Standard may already be enabled or region-specific ARN needed"

# Create custom IAM policy with the required permissions
echo "Creating custom IAM policy with required permissions..."
POLICY_EXISTS=$(aws iam get-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME" --query 'Policy.Arn' --output text 2>/dev/null)
if [ "$POLICY_EXISTS" = "None" ] || [ -z "$POLICY_EXISTS" ]; then
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
    echo "Policy created successfully."
else
    echo "Policy already exists: $POLICY_EXISTS"
fi

# Get the Policy ARN
POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"

# Create IAM Role with trust policy allowing the current user to assume it
echo "Creating IAM Role: $ROLE_NAME"
ROLE_EXISTS=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null)
if [ "$ROLE_EXISTS" = "None" ] || [ -z "$ROLE_EXISTS" ]; then
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
    echo "Role created successfully."
else
    echo "Role already exists: $ROLE_EXISTS"
fi

# Attach the custom policy to the role
echo "Attaching custom policy to role..."
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
check_error

# Get the Role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)
check_error

# Save details to file
echo "=================================================="
echo "Setup completed successfully!"
echo "=================================================="
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
echo "=== NEXT STEPS ==="
echo "To use this role with your Sahl application:"
echo "1. Copy this Role ARN: $ROLE_ARN"
echo "2. Provide your AWS Access Key ID and Secret Access Key to the application"
echo "3. The application will assume this role to access your AWS resources"
echo ""
echo "If you encounter issues, check TROUBLESHOOTING.md for help"
echo ""
echo "Press any key to exit..."
read -n 1