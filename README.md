# AWS Security Hub Setup Scripts

This repository contains scripts to automatically set up AWS Security Hub with the required IAM roles and permissions for the Sahl security monitoring application.

## Quick Start

### Option 1: One-line setup (with parameters)
```bash
curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-service-account-setup.sh | bash -s YOUR_ACCOUNT_ID YOUR_REGION
```

**Example:**
```bash
curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-service-account-setup.sh | bash -s 123456789012 us-east-1
```

### Option 2: Interactive setup
```bash
curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-setup-interactive.sh | bash
```

### Option 3: Download and run locally
```bash
curl -o aws-setup.sh https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/aws-service-account-setup.sh
chmod +x aws-setup.sh
./aws-setup.sh
```

## Prerequisites

1. **AWS CLI installed** - Install from https://aws.amazon.com/cli/
2. **AWS credentials configured** - Run `aws configure` with your:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region
   - Default output format (json)

## Troubleshooting

If you encounter issues:

1. **"Unable to parse config file"** - Run the config fix script:
   ```bash
   curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/fix-aws-config.sh | bash
   ```

2. **"AWS credentials not configured"** - Set up your credentials:
   ```bash
   aws configure
   ```

3. **Check detailed troubleshooting guide:**
   ```bash
   curl -sSL https://raw.githubusercontent.com/getsahl-io/automation-script/refs/heads/main/TROUBLESHOOTING.md
   ```

## What This Script Does

1. Validates AWS CLI and credentials
2. Sets up AWS Config (if not already enabled)
3. Enables AWS Security Hub
4. Creates a custom IAM policy with read-only permissions
5. Creates an IAM role that can be assumed by your AWS user
6. Saves all details to `~/aws-security-hub-details.txt`

## Permissions Granted

The created IAM role has these read-only permissions:
- **IAM**: ListUsers, ListAccessKeys, ListMFADevices, GetAccountSummary
- **S3**: ListBuckets, GetBucketPolicyStatus, GetBucketEncryption
- **CloudTrail**: DescribeTrails, GetEventSelectors
- **EC2**: DescribeSecurityGroups
- **Config**: GetComplianceSummaryByConfigRule
- **Security Hub**: GetFindings

## Security

- All resources are created with read-only permissions
- The IAM role can only be assumed by your AWS user
- No permanent credentials are stored
- Details are saved locally for your reference

## Support

If you encounter issues, check the troubleshooting guide or contact support with the error details and your setup information.
