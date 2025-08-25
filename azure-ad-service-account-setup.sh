#!/bin/bash
# ============================================================
# Azure AD Service Account Setup Script - Complete with Auto-Auth
# ============================================================
set -e

# Constants
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000" # Microsoft Graph API
APP_NAME="sahl-automation-app"

# ------------------------------------------------------------
# 1. Handle Cloud Shell Authentication
# ------------------------------------------------------------
echo "🔐 Checking and fixing authentication..."

# Function to test authentication
test_auth() {
    az account show --query user.name -o tsv &>/dev/null
    return $?
}

# Function to test Graph API access specifically
test_graph_auth() {
    az ad app list --query "[0].appId" -o tsv &>/dev/null
    return $?
}

# Test current authentication
if ! test_auth; then
    echo "⚠️  No authentication detected. Please login first."
    echo "Run: az login"
    exit 1
fi

# Test Graph API access
if ! test_graph_auth; then
    echo "⚠️  Graph API authentication issue detected. Attempting to fix..."
    
    # Try the specific scope login for Cloud Shell
    echo "Trying Cloud Shell specific authentication..."
    if az login --scope 74658136-14ec-4630-ad9b-26e160ff0fc6/.default --only-show-errors 2>/dev/null; then
        echo "✅ Authentication fixed with Cloud Shell scope"
    else
        echo "⚠️  Cloud Shell scope failed, trying alternative method..."
        # Alternative approach - refresh token
        if az account get-access-token --scope https://graph.microsoft.com/.default --only-show-errors >/dev/null 2>&1; then
            echo "✅ Graph API access token refreshed"
        else
            echo "❌ Authentication fix failed"
            echo "Please manually run one of these commands:"
            echo "  az login --scope 74658136-14ec-4630-ad9b-26e160ff0fc6/.default"
            echo "  or"
            echo "  az login"
            exit 1
        fi
    fi
    
    # Wait for authentication to propagate
    echo "⏳ Waiting for authentication to propagate..."
    sleep 5
fi

# Verify authentication is working
CURRENT_USER=$(az account show --query user.name -o tsv 2>/dev/null || echo "unknown")
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "✅ Authenticated as: $CURRENT_USER"
echo "✅ Tenant ID: $TENANT_ID"
echo "✅ Subscription ID: $SUBSCRIPTION_ID"

# ------------------------------------------------------------
# 2. Check if App Already Exists
# ------------------------------------------------------------
echo "🔍 Checking if app already exists..."

EXISTING_APP=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_APP" ] && [ "$EXISTING_APP" != "null" ]; then
    echo "⚠️  App '$APP_NAME' already exists with ID: $EXISTING_APP"
    read -p "Do you want to continue with existing app? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        APP_ID="$EXISTING_APP"
        APP_INFO=$(az ad app show --id "$APP_ID")
        OBJECT_ID=$(echo "$APP_INFO" | jq -r '.id')
        
        # Get service principal
        SP_INFO=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0]" 2>/dev/null)
        if [ "$SP_INFO" = "null" ] || [ -z "$SP_INFO" ]; then
            echo "🔧 Creating missing Service Principal..."
            SP_INFO=$(az ad sp create --id "$APP_ID")
        fi
        SP_OBJECT_ID=$(echo "$SP_INFO" | jq -r '.id')
        
        echo "✅ Using existing app - Client ID: $APP_ID"
        echo "✅ App Object ID: $OBJECT_ID"
        echo "✅ Service Principal Object ID: $SP_OBJECT_ID"
    else
        echo "❌ Aborted by user"
        exit 1
    fi
else
    # ------------------------------------------------------------
    # 3. Create New Azure AD App Registration
    # ------------------------------------------------------------
    echo "🚀 Creating Azure AD app registration: $APP_NAME..."
    
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
fi

# ------------------------------------------------------------
# 4. Add Microsoft Graph API Permissions
# ------------------------------------------------------------
echo "🔧 Adding Microsoft Graph API permissions..."

# Function to add permission with retry
add_permission() {
    local permission_id=$1
    local permission_name=$2
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if az ad app permission add --id "$APP_ID" --api "$GRAPH_APP_ID" --api-permissions "$permission_id=Role" --only-show-errors 2>/dev/null; then
            echo "  ✅ $permission_name added"
            return 0
        else
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                echo "  ⚠️  $permission_name failed, retrying... ($retry/$max_retries)"
                sleep 2
            else
                echo "  ❌ $permission_name failed after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Add permissions with retry logic
add_permission "df021288-bdef-4463-88db-98f22de89214" "User.Read.All"
add_permission "5b567255-7703-4780-807c-7be8301ae99b" "Group.Read.All"
add_permission "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30" "Application.Read.All"
add_permission "7ab1d382-f21e-4acd-a863-ba3e13f7da61" "Directory.Read.All"
add_permission "246dd0d5-5bd0-4def-940b-0421030a5b68" "Policy.Read.All"
add_permission "483bed4a-2ad3-4361-a73b-c83ccdbdc53c" "RoleManagement.Read.Directory"

echo "✅ Microsoft Graph permissions added."

# ------------------------------------------------------------
# 5. Grant Admin Consent
# ------------------------------------------------------------
echo "🔑 Granting admin consent..."
echo "⚠️  Note: This requires Global Administrator or Privileged Role Administrator privileges"

# Wait for permissions to propagate
echo "⏳ Waiting for permissions to propagate..."
sleep 10

# Try admin consent with multiple approaches
CONSENT_SUCCESS=false

# Method 1: Direct admin consent
if az ad app permission admin-consent --id "$APP_ID" --only-show-errors 2>/dev/null; then
    echo "✅ Admin consent granted successfully"
    CONSENT_SUCCESS=true
else
    echo "⚠️  Direct admin consent failed, trying alternative method..."
    
    # Method 2: Grant permissions individually
    if az ad app permission grant --id "$APP_ID" --api "$GRAPH_APP_ID" --only-show-errors 2>/dev/null; then
        echo "✅ Permissions granted (may still require admin consent in portal)"
    else
        echo "⚠️  Permission grant also failed"
    fi
fi

if [ "$CONSENT_SUCCESS" = false ]; then
    echo "⚠️  Admin consent could not be completed via CLI"
    echo "   Please grant manually in Azure Portal:"
    echo "   https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/ApiPermissions/appId/$APP_ID"
fi

# ------------------------------------------------------------
# 6. Create Client Secret
# ------------------------------------------------------------
echo "🔐 Creating client secret..."

SECRET_INFO=$(az ad app credential reset --id "$APP_ID" --append --display-name "automation-secret-$(date +%Y%m%d-%H%M)" --years 2)
CLIENT_SECRET=$(echo "$SECRET_INFO" | jq -r '.password')
echo "✅ Client secret created (expires in 2 years)"

# ------------------------------------------------------------
# 7. Assign Subscription Role
# ------------------------------------------------------------
echo "🛡️ Assigning Reader role on subscription..."

# Check if role assignment already exists
EXISTING_ASSIGNMENT=$(az role assignment list --assignee "$SP_OBJECT_ID" --scope "/subscriptions/$SUBSCRIPTION_ID" --role "Reader" --query "[0].id" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_ASSIGNMENT" ] && [ "$EXISTING_ASSIGNMENT" != "null" ]; then
    echo "✅ Reader role already assigned"
else
    if az role assignment create --assignee "$SP_OBJECT_ID" --role "Reader" --scope "/subscriptions/$SUBSCRIPTION_ID" --only-show-errors 2>/dev/null; then
        echo "✅ Reader role assigned successfully"
    else
        echo "⚠️  Role assignment failed - you may need additional permissions"
        echo "   You can assign this manually in Azure Portal if needed"
    fi
fi

# ------------------------------------------------------------
# 8. Final Summary and Verification
# ------------------------------------------------------------
echo ""
echo "🎉 Azure AD Service Account setup completed!"
echo ""
echo "=== CONFIGURATION SUMMARY ==="
echo "App Name: $APP_NAME"
echo "Client ID: $APP_ID"
echo "Object ID: $OBJECT_ID"
echo "Service Principal Object ID: $SP_OBJECT_ID"
echo "Tenant ID: $TENANT_ID"
echo "Subscription ID: $SUBSCRIPTION_ID"
echo ""
echo "=== CLIENT SECRET ==="
echo "⚠️  IMPORTANT: Save this secret securely!"
echo "Client Secret: $CLIENT_SECRET"
echo ""
echo "=== AUTHENTICATION TEST COMMAND ==="
echo "az login --service-principal -u '$APP_ID' -p '$CLIENT_SECRET' --tenant '$TENANT_ID'"
echo ""
echo "=== VERIFICATION LINKS ==="
echo "App Overview: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$APP_ID"
echo "API Permissions: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/ApiPermissions/appId/$APP_ID"
echo "Certificates & Secrets: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/$APP_ID"
echo ""
echo "=== NEXT STEPS ==="
echo "1. Verify admin consent status in the API Permissions page"
echo "2. Test service principal authentication"
echo "3. Store credentials in Azure Key Vault or secure location"
echo "4. Configure your automation tools with these credentials"
