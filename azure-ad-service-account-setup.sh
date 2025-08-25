#!/bin/bash
# ============================================================
# Azure AD Service Account Setup Script (Fixed)
# ============================================================
set -e

# Constants
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000" # Microsoft Graph API

# ------------------------------------------------------------
# 1. Create Azure AD App Registration
# ------------------------------------------------------------
APP_NAME="sahl-automation-app"
echo "🚀 Creating Azure AD app registration: $APP_NAME..."

# Updated command without deprecated parameter
APP_INFO=$(az ad app create --display-name "$APP_NAME" --sign-in-audience "AzureADMyOrg")
APP_ID=$(echo "$APP_INFO" | jq -r '.appId')
OBJECT_ID=$(echo "$APP_INFO" | jq -r '.id')
echo "✅ App registered with Client ID: $APP_ID"
echo "✅ App Object ID: $OBJECT_ID"

# Create Service Principal
echo "🔧 Creating Service Principal..."
SP_INFO=$(az ad sp create --id "$APP_ID")
SP_OBJECT_ID=$(echo "$SP_INFO" | jq -r '.id')
echo "✅ Service Principal created with Object ID: $SP_OBJECT_ID"

# ------------------------------------------------------------
# 2. Add Microsoft Graph API Permissions
# ------------------------------------------------------------
echo "🔧 Adding Microsoft Graph API permissions..."

# User.Read.All (Application permission)
az ad app permission add --id "$APP_ID" --api "$GRAPH_APP_ID" --api-permissions df021288-bdef-4463-88db-98f22de89214=Role

# Group.Read.All (Application permission)
az ad app permission add --id "$APP_ID" --api "$GRAPH_APP_ID" --api-permissions 5b567255-7703-4780-807c-7be8301ae99b=Role

# Application.Read.All (Application permission)
az ad app permission add --id "$APP_ID" --api "$GRAPH_APP_ID" --api-permissions 9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30=Role

# Directory.Read.All (Application permission)
az ad app permission add --id "$APP_ID" --api "$GRAPH_APP_ID" --api-permissions 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role

# Policy.Read.All (Application permission)
az ad app permission add --id "$APP_ID" --api "$GRAPH_APP_ID" --api-permissions 246dd0d5-5bd0-4def-940b-0421030a5b68=Role

# RoleManagement.Read.Directory (Application permission)
az ad app permission add --id "$APP_ID" --api "$GRAPH_APP_ID" --api-permissions 483bed4a-2ad3-4361-a73b-c83ccdbdc53c=Role

echo "✅ Microsoft Graph permissions added."

# ------------------------------------------------------------
# 3. Grant Admin Consent
# ------------------------------------------------------------
echo "🔑 Granting admin consent..."
echo "⚠️  Note: This requires Global Administrator or Privileged Role Administrator privileges"

# Wait a moment for permissions to propagate
echo "⏳ Waiting for permissions to propagate..."
sleep 10

az ad app permission admin-consent --id "$APP_ID"
echo "✅ Admin consent granted."

# ------------------------------------------------------------
# 4. Create Client Secret
# ------------------------------------------------------------
echo "🔐 Creating client secret..."
SECRET_INFO=$(az ad app credential reset --id "$APP_ID" --append --display-name "automation-secret" --years 2)
CLIENT_SECRET=$(echo "$SECRET_INFO" | jq -r '.password')
echo "✅ Client secret created (expires in 2 years)"

# ------------------------------------------------------------
# 5. Assign Role to Subscription (optional, for automation)
# ------------------------------------------------------------
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "🛡️ Assigning Reader role on subscription: $SUBSCRIPTION_ID"
az role assignment create \
  --assignee "$SP_OBJECT_ID" \
  --role "Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --condition-version "2.0" || echo "⚠️  Role assignment may have failed - check permissions"

echo "✅ Role assignment completed."

# ------------------------------------------------------------
# 6. Display Configuration Summary
# ------------------------------------------------------------
echo ""
echo "🎉 Azure AD Service Account setup completed successfully!"
echo ""
echo "=== CONFIGURATION SUMMARY ==="
echo "App Name: $APP_NAME"
echo "Client ID (Application ID): $APP_ID"
echo "Object ID: $OBJECT_ID"
echo "Service Principal Object ID: $SP_OBJECT_ID"
echo "Tenant ID: $TENANT_ID"
echo "Subscription ID: $SUBSCRIPTION_ID"
echo ""
echo "=== CLIENT SECRET ==="
echo "⚠️  IMPORTANT: Save this secret securely - it won't be displayed again!"
echo "Client Secret: $CLIENT_SECRET"
echo ""
echo "=== PERMISSIONS GRANTED ==="
echo "✓ User.Read.All"
echo "✓ Group.Read.All" 
echo "✓ Application.Read.All"
echo "✓ Directory.Read.All"
echo "✓ Policy.Read.All"
echo "✓ RoleManagement.Read.Directory"
echo ""
echo "=== NEXT STEPS ==="
echo "1. Verify permissions in Azure Portal: Azure AD > App registrations > $APP_NAME > API permissions"
echo "2. Test the service account with your automation tools"
echo "3. Store the Client ID, Tenant ID, and Client Secret securely (e.g., Key Vault)"
echo ""
echo "🔗 Azure Portal: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$APP_ID"
