#!/bin/bash

# ============================================================
# Azure AD Service Account Setup Script
# ============================================================

set -e

# Constants
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000" # Microsoft Graph API

# ------------------------------------------------------------
# 1. Create Azure AD App Registration
# ------------------------------------------------------------
APP_NAME="sahl-automation-app"
echo "🚀 Creating Azure AD app registration: $APP_NAME..."

APP_INFO=$(az ad app create --display-name $APP_NAME --available-to-other-tenants false)
APP_ID=$(echo $APP_INFO | jq -r '.appId')

echo "✅ App registered with Client ID: $APP_ID"

# Create Service Principal
SP_INFO=$(az ad sp create --id $APP_ID)
APP_OBJECT_ID=$(echo $SP_INFO | jq -r '.id')

echo "✅ Service Principal created with Object ID: $APP_OBJECT_ID"

# ------------------------------------------------------------
# 2. Add Microsoft Graph API Permissions
# ------------------------------------------------------------
echo "🔧 Adding Microsoft Graph API permissions..."

# User.Read.All
az ad app permission add --id $APP_ID --api $GRAPH_APP_ID --api-permissions df021288-bdef-4463-88db-98f22de89214=Role

# Group.Read.All
az ad app permission add --id $APP_ID --api $GRAPH_APP_ID --api-permissions 5b567255-7703-4780-807c-7be8301ae99b=Role

# Application.Read.All
az ad app permission add --id $APP_ID --api $GRAPH_APP_ID --api-permissions 741f803b-c850-494e-b5df-cde7c675a1ca=Role

# Directory.Read.All
az ad app permission add --id $APP_ID --api $GRAPH_APP_ID --api-permissions 06da0dbc-49e2-44d2-8312-53f166ab848a=Role

echo "✅ Microsoft Graph permissions added."

# ------------------------------------------------------------
# 3. Grant Admin Consent
# ------------------------------------------------------------
echo "🔑 Granting admin consent..."
az ad app permission admin-consent --id $APP_ID
echo "✅ Admin consent granted."

# ------------------------------------------------------------
# 4. Assign Role to Subscription (optional, for automation)
# ------------------------------------------------------------
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "🛡️ Assigning Reader role on subscription: $SUBSCRIPTION_ID"

az role assignment create \
  --assignee $APP_OBJECT_ID \
  --role Reader \
  --scope /subscriptions/$SUBSCRIPTION_ID

echo "🎉 Azure AD Service Account setup completed successfully!"
