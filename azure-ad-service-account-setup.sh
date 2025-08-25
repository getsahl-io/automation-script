#!/bin/bash

# Azure AD + RBAC Service Principal Setup Script
# This script creates a service principal with RBAC roles + Graph API permissions
# Must be run by an Azure AD Global Administrator + Subscription Owner

set -e

echo "🚀 Starting Azure AD + Service Principal Setup..."

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "📋 Using subscription: $SUBSCRIPTION_ID"

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
TENANT_ID=$(echo $SP_OUTPUT | jq -r '.tenantId')

echo "✅ Service principal created successfully!"
echo "   Client ID: $CLIENT_ID"

# Assign RBAC roles
echo "🔒 Assigning additional RBAC roles..."

az role assignment create --assignee $CLIENT_ID --role "Security Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"
az role assignment create --assignee $CLIENT_ID --role "Storage Blob Data Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"
az role assignment create --assignee $CLIENT_ID --role "Key Vault Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"
az role assignment create --assignee $CLIENT_ID --role "Monitoring Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"

echo "✅ RBAC roles assigned."

# Get the App Object ID (needed for Graph permissions)
APP_OBJECT_ID=$(az ad app list --filter "appId eq '$CLIENT_ID'" --query "[0].id" -o tsv)

if [ -z "$APP_OBJECT_ID" ]; then
  echo "❌ Could not find App Object ID for clientId $CLIENT_ID"
  exit 1
fi

echo "📌 App Object ID: $APP_OBJECT_ID"

# Microsoft Graph API App ID (fixed for all tenants)
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"

echo "🔧 Adding Microsoft Graph API permissions..."

# User.Read.All
az ad app permission add --id $APP_OBJECT_ID --api $GRAPH_APP_ID --api-permissions "df021288-bdef-4463-88db-98f22de89214=Role"

# Group.Read.All
az ad app permission add --id $APP_OBJECT_ID --api $GRAPH_APP_ID --api-permissions "5b567255-7703-4780-807c-7be8301ae99b=Role"

# Application.Read.All
az ad app permission add --id $APP_OBJECT_ID --api $GRAPH_APP_ID --api-permissions "e2af2b9e-3a82-44c2-b0c9-9691c07f07d2=Role"

# Directory.Read.All
az ad app permission add --id $APP_OBJECT_ID --api $GRAPH_APP_ID --api-permissions "06da0dbc-49e2-44d2-8312-53f166ab848a=Role"

# Policy.Read.All
az ad app permission add --id $APP_OBJECT_ID --api $GRAPH_APP_ID --api-permissions "246dd0d5-5bd0-4def-940b-0421030a5b68=Role"

# RoleManagement.Read.Directory
az ad app permission add --id $APP_OBJECT_ID --api $GRAPH_APP_ID --api-permissions "9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8=Role"

echo "✅ Microsoft Graph permissions added."

# Grant admin consent (requires Global Admin privileges)
echo "🔑 Granting admin consent..."
az ad app permission grant --id $APP_OBJECT_ID --api $GRAPH_APP_ID
az ad app permission admin-consent --id $APP_OBJECT_ID

echo "✅ Admin consent granted."

# Wait for propagation
echo "⏳ Waiting for role & permission propagation..."
sleep 30

# Save configuration
CONFIG_FILE="azure-ad-service-account-credentials.json"
cat > $CONFIG_FILE << EOF
{
  "tenantId": "$TENANT_ID",
  "clientId": "$CLIENT_ID",
  "clientSecret": "$CLIENT_SECRET",
  "subscriptionId": "$SUBSCRIPTION_ID",
  "appObjectId": "$APP_OBJECT_ID",
  "createdOn": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "permissions": {
    "rbac": [
      "Reader",
      "Security Reader",
      "Storage Blob Data Reader",
      "Key Vault Reader",
      "Monitoring Reader"
    ],
    "graph": [
      "User.Read.All",
      "Group.Read.All",
      "Application.Read.All",
      "Directory.Read.All",
      "Policy.Read.All",
      "RoleManagement.Read.Directory"
    ]
  }
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
echo "App Object ID: $APP_OBJECT_ID"
echo "================================"
echo ""
echo "💾 Configuration saved to: $CONFIG_FILE"
echo "⚠️  IMPORTANT: Save these credentials securely!"
echo "💡 Use these credentials in your application's Azure integration setup."
echo ""
echo "🔧 Roles assigned:"
echo "   - Reader"
echo "   - Security Reader"
echo "   - Storage Blob Data Reader"
echo "   - Key Vault Reader"
echo "   - Monitoring Reader"
echo ""
echo "🔧 Graph API Permissions:"
echo "   - User.Read.All"
echo "   - Group.Read.All"
echo "   - Application.Read.All"
echo "   - Directory.Read.All"
echo "   - Policy.Read.All"
echo "   - RoleManagement.Read.Directory"
echo ""
