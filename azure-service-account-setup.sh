#!/bin/bash

# Azure Service Principal Setup Script for Cloud Shell
# This script creates a service principal with necessary permissions for security monitoring

set -e

echo "🚀 Starting Azure Service Principal Setup..."

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

# Assign additional required roles
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

# Wait for role propagation
echo "⏳ Waiting for role assignments to propagate..."
sleep 30

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
echo "⚠️  IMPORTANT: Save these credentials securely!"
echo "💡 Use these credentials in your application's Azure integration setup."
echo ""
echo "🔧 Roles assigned:"
echo "   - Reader (subscription level)"
echo "   - Security Reader (subscription level)"
echo "   - Storage Blob Data Reader (subscription level)"
echo "   - Key Vault Reader (subscription level)"
echo "   - Monitoring Reader (subscription level)"
