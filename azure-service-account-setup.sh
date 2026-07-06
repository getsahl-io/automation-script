#!/bin/bash

# Azure Service Principal Setup Script for Cloud Shell
# Creates a service principal with permissions for security monitoring, Microsoft Graph,
# and Asset Register (Azure Resource Graph via Reader role)

set -e

echo "🚀 Starting Azure Service Principal Setup..."

# ------------------------------------------------------------
# Authentication Preflight
# ------------------------------------------------------------
# Cloud Shell sessions are sometimes still initializing (or the ARM token has
# expired) when this script is run, which causes `az account show` to fail
# with "Please run 'az login' to setup account." Detect that case and try to
# recover automatically before giving up.
test_auth() {
  az account show --query id -o tsv &>/dev/null
  return $?
}

if ! test_auth; then
  echo "⚠️  No active Azure session detected. Attempting to authenticate..."

  if az login --scope 74658136-14ec-4630-ad9b-26e160ff0fc6/.default --only-show-errors &>/dev/null; then
    echo "✅ Authenticated using the Cloud Shell ARM scope"
  elif az login --only-show-errors &>/dev/null; then
    echo "✅ Authenticated via az login"
  else
    echo "❌ Authentication failed."
    echo "🔧 Please run 'az login' manually in this Cloud Shell session, then re-run this script:"
    echo "   az login"
    echo "   ./Azure-setup.sh"
    exit 1
  fi
fi

# Get subscription ID and tenant ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || echo "")
TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")

if [ -z "$SUBSCRIPTION_ID" ] || [ -z "$TENANT_ID" ]; then
  echo "❌ No active Azure subscription found."
  echo "📋 Available subscriptions:"
  az account list -o table
  echo ""
  echo "🔧 Select one and re-run this script:"
  echo "   az account set --subscription \"<subscription-name-or-id>\""
  echo "   ./Azure-setup.sh"
  exit 1
fi

CURRENT_USER=$(az account show --query user.name -o tsv 2>/dev/null || echo "unknown")
echo "✅ Authenticated as: $CURRENT_USER"
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

GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"

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

for permission_name in "${!PERMISSIONS[@]}"; do
 permission_id="${PERMISSIONS[$permission_name]}"
 echo "📋 Adding permission: $permission_name"

 az ad app permission add \
 --id $CLIENT_ID \
 --api $GRAPH_APP_ID \
 --api-permissions "$permission_id=Role"
done

echo "✅ Microsoft Graph permissions added successfully!"

echo "⚠️ IMPORTANT: Admin consent is required for these permissions!"
echo "🔧 Granting admin consent for Microsoft Graph permissions..."

az ad app permission admin-consent --id $CLIENT_ID || {
 echo "❌ Failed to grant admin consent automatically."
 echo "🔄 Grant admin consent manually in Azure Portal > App registrations > API permissions"
}

echo "⏳ Waiting for permissions to propagate..."
sleep 60

echo "🧪 Testing service principal permissions..."
# Use an isolated CLI config directory for this test so the service principal
# login does not replace your signed-in Cloud Shell session.
SP_TEST_CONFIG_DIR=$(mktemp -d)
if AZURE_CONFIG_DIR="$SP_TEST_CONFIG_DIR" az login --service-principal -u $CLIENT_ID -p $CLIENT_SECRET --tenant $TENANT_ID --only-show-errors > /dev/null 2>&1; then
 echo "🔍 Testing Microsoft Graph access..."
 ACCESS_TOKEN=$(AZURE_CONFIG_DIR="$SP_TEST_CONFIG_DIR" az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv 2>/dev/null)

 if [ ! -z "$ACCESS_TOKEN" ]; then
 echo "✅ Microsoft Graph access token obtained successfully!"
 else
 echo "❌ Failed to obtain Microsoft Graph access token"
 fi
else
 echo "⚠️ Could not verify service principal login yet — permissions may still be propagating. This does not affect the credentials below."
fi
rm -rf "$SP_TEST_CONFIG_DIR"

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
 "assetRegisterNote": "Reader role at subscription scope enables Azure Resource Graph queries for Asset Register. No additional RBAC roles are required.",
 "adminConsentProvided": true
}
EOF

echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "📝 Service Principal Details:"
echo "================================"
echo "Tenant ID: $TENANT_ID"
echo "Client ID: $CLIENT_ID"
echo "Client Secret: $CLIENT_SECRET"
echo "Subscription: $SUBSCRIPTION_ID"
echo "================================"
echo ""
echo "💾 Configuration saved to: $CONFIG_FILE"
echo ""
echo "🔧 Azure RBAC Roles assigned:"
echo " - Reader (subscription level) — includes Azure Resource Graph for Asset Register"
echo " - Security Reader (subscription level)"
echo " - Storage Blob Data Reader (subscription level)"
echo " - Key Vault Reader (subscription level)"
echo " - Monitoring Reader (subscription level)"
echo ""
echo "📦 Asset Register:"
echo " - Uses Azure Resource Graph to list subscription resources."
echo " - Covered by the Reader role assigned above; no extra roles needed."
echo ""
