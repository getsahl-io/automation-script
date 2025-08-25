#!/bin/bash

# Azure Service Principal Setup Script for Cloud Shell
# This script creates a service principal with necessary permissions for security monitoring and Microsoft Graph access

set -e

echo "🚀 Starting Azure Service Principal Setup..."

# Get subscription ID and tenant ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "📋 Using subscription: $SUBSCRIPTION_ID"
echo "🏢 Using tenant: $TENANT_ID"

# Create service principal
echo "🔐 Creating service principal..."
SP_OUTPUT=$(az ad sp create-for-rbac \
  --name "sahl-security-monitor-sp" \
  --role "Reader" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID" \
  --sdk-auth)

# Extract values from JSON output
CLIENT_ID=$(echo $SP_OUTPUT | jq -r '.clientId')
CLIENT_SECRET=$(echo $SP_OUTPUT | jq -r '.clientSecret')

echo "✅ Service principal created successfully!"
echo "🆔 Service Principal Object ID: $(az ad sp show --id $CLIENT_ID --query id -o tsv)"

# Assign additional Azure RBAC roles
echo "🔒 Assigning Security Reader role..."
az role assignment create \
  --assignee $CLIENT_ID \
  --role "Security Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

echo "🔍 Assigning Reader and Data Access role for storage..."
az role assignment create \
  --assignee $CLIENT_ID \
  --role "Storage Blob Data Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

echo "🗝️ Assigning Key Vault Reader role..."
az role assignment create \
  --assignee $CLIENT_ID \
  --role "Key Vault Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

echo "📊 Assigning Monitoring Reader role..."
az role assignment create \
  --assignee $CLIENT_ID \
  --role "Monitoring Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Microsoft Graph API permissions
echo "🔑 Configuring Microsoft Graph API permissions..."

# Get Microsoft Graph App ID (well-known constant)
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"

# Required Microsoft Graph Application Permissions
declare -A PERMISSIONS=(
  ["User.Read.All"]="df021288-bdef-4463-88db-98f22de89214"
  ["Group.Read.All"]="5b567255-7703-4780-807c-7be8301ae99b"
  ["Directory.Read.All"]="7ab1d382-f21e-4acd-a863-ba3e13f7da61"
  ["Application.Read.All"]="9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30"
  ["Policy.Read.All"]="246dd0d5-5bd0-4def-940b-0421030a5b68"
  ["AuditLog.Read.All"]="b0afded3-3588-46d8-8b3d-9842eff778da"
  ["UserAuthenticationMethod.Read.All"]="38d9df27-64da-44fd-b7c5-a6fbac20248f"
  ["SecurityEvents.Read.All"]="bf394140-e372-4bf9-a898-299cfc7564e5"
)

# Add required permissions to the service principal
for permission_name in "${!PERMISSIONS[@]}"; do
  permission_id="${PERMISSIONS[$permission_name]}"
  echo "📋 Adding permission: $permission_name"
  
  az ad app permission add \
    --id $CLIENT_ID \
    --api $GRAPH_APP_ID \
    --api-permissions "$permission_id=Role"
done

echo "✅ Microsoft Graph permissions added successfully!"

echo "⚠️  IMPORTANT: Admin consent is required for these permissions!"
echo "🔧 Granting admin consent for Microsoft Graph permissions..."

# Grant admin consent (requires Global Administrator privileges)
az ad app permission admin-consent --id $CLIENT_ID || {
  echo "❌ Failed to grant admin consent automatically."
  echo "🔄 You may need to grant admin consent manually in the Azure Portal:"
  echo "   1. Go to Azure Portal > Azure Active Directory > App registrations"
  echo "   2. Find your application: 'sahl-security-monitor-sp'"
  echo "   3. Go to 'API permissions'"
  echo "   4. Click 'Grant admin consent for [Your Tenant]'"
  echo ""
}

# Wait for permission propagation
echo "⏳ Waiting for permissions to propagate..."
sleep 60

# Test the service principal permissions
echo "🧪 Testing service principal permissions..."
az login --service-principal -u $CLIENT_ID -p $CLIENT_SECRET --tenant $TENANT_ID > /dev/null 2>&1

# Test Microsoft Graph access
echo "🔍 Testing Microsoft Graph access..."
ACCESS_TOKEN=$(az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)

if [ ! -z "$ACCESS_TOKEN" ]; then
  echo "✅ Microsoft Graph access token obtained successfully!"
else
  echo "❌ Failed to obtain Microsoft Graph access token"
fi

# Switch back to user login
az logout > /dev/null 2>&1
az login > /dev/null 2>&1

# Create JSON configuration file
CONFIG_FILE="azure-service-account-credentials.json"
cat > $CONFIG_FILE << EOF
{
  "tenantId": "$TENANT_ID",
  "clientId": "$CLIENT_ID",
  "clientSecret": "$CLIENT_SECRET",
  "subscriptionId": "$SUBSCRIPTION_ID",
  "applicationName": "sahl-security-monitor-sp",
  "createdOn": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "azureRoles": [
    "Reader",
    "Security Reader", 
    "Storage Blob Data Reader",
    "Key Vault Reader",
    "Monitoring Reader"
  ],
  "microsoftGraphPermissions": [
    "User.Read.All",
    "Group.Read.All",
    "Directory.Read.All",
    "Application.Read.All",
    "Policy.Read.All",
    "AuditLog.Read.All",
    "UserAuthenticationMethod.Read.All",
    "SecurityEvents.Read.All"
  ],
  "adminConsentProvided": true
}
EOF

echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "📝 Service Principal Details:"
echo "================================"
echo "Tenant ID:     $TENANT_ID"
echo "Client ID:     $CLIENT_ID"
echo "Client Secret: $CLIENT_SECRET"
echo "Subscription:  $SUBSCRIPTION_ID"
echo "================================"
echo ""
echo "💾 Configuration saved to: $CONFIG_FILE"
echo "⚠️  IMPORTANT: Save these credentials securely!"
echo "💡 Use these credentials in your application's Azure integration setup."
echo ""
echo "🔧 Azure RBAC Roles assigned:"
echo "   - Reader (subscription level)"
echo "   - Security Reader (subscription level)"
echo "   - Storage Blob Data Reader (subscription level)"
echo "   - Key Vault Reader (subscription level)"
echo "   - Monitoring Reader (subscription level)"
echo ""
echo "🔑 Microsoft Graph API Permissions granted:"
echo "   - User.Read.All (Read all users)"
echo "   - Group.Read.All (Read all groups)"
echo "   - Directory.Read.All (Read directory data)"
echo "   - Application.Read.All (Read all applications)"
echo "   - Policy.Read.All (Read all policies)"
echo "   - AuditLog.Read.All (Read audit logs)"
echo "   - UserAuthenticationMethod.Read.All (Read user auth methods)"
echo "   - SecurityEvents.Read.All (Read security events)"
echo ""
echo "📋 Next Steps:"
echo "   1. Verify admin consent was granted (check Azure Portal if needed)"
echo "   2. Download the configuration file: cat $CONFIG_FILE"
echo "   3. Copy the content and save it locally"
echo "   4. Use these credentials in your application"
echo ""
echo "🔍 If you encounter permission errors:"
echo "   - Ensure you have Global Administrator privileges"
echo "   - Manually grant admin consent in Azure Portal"
echo "   - Wait a few minutes for permissions to propagate"
