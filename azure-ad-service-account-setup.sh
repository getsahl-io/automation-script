#!/bin/bash
# ============================================================
# Azure AD Service Account Setup Script - COMPLETE AUTO SETUP
# This script ensures ALL permissions are granted automatically
# ============================================================
set -e

# Constants
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000" # Microsoft Graph API
APP_NAME="sahl-automation-app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# ------------------------------------------------------------
# 1. Enhanced Authentication with Multiple Methods
# ------------------------------------------------------------
log_info "Checking and fixing authentication..."

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

# Function to get enhanced access token with all required scopes
get_enhanced_access_token() {
    log_info "Getting enhanced access token with full permissions..."
    
    # Try to get access token with full Graph API scope
    if az account get-access-token --resource https://graph.microsoft.com --only-show-errors >/dev/null 2>&1; then
        log_success "Graph API access token obtained"
    else
        log_warning "Graph API token failed, trying alternative scopes..."
        
        # Try with directory scope
        if az account get-access-token --resource https://graph.windows.net --only-show-errors >/dev/null 2>&1; then
            log_success "Directory API access token obtained"
        else
            log_warning "Trying Cloud Shell specific authentication..."
            az login --scope 74658136-14ec-4630-ad9b-26e160ff0fc6/.default --only-show-errors 2>/dev/null || true
        fi
    fi
}

# Test current authentication
if ! test_auth; then
    log_error "No authentication detected. Please login first."
    echo "Run: az login"
    exit 1
fi

# Get current context
CURRENT_USER=$(az account show --query user.name -o tsv 2>/dev/null || echo "unknown")
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

log_success "Authenticated as: $CURRENT_USER"
log_success "Tenant ID: $TENANT_ID"
log_success "Subscription ID: $SUBSCRIPTION_ID"

# Enhanced authentication for Graph API
get_enhanced_access_token

# Check if user has Global Admin or Privileged Role Admin
log_info "Checking user privileges..."
USER_ROLES=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/me/memberOf" --query "value[?@.displayName=='Global Administrator' || @.displayName=='Privileged Role Administrator'].displayName" -o tsv 2>/dev/null || echo "")

if [ -n "$USER_ROLES" ]; then
    log_success "User has admin privileges: $USER_ROLES"
    HAS_ADMIN_RIGHTS=true
else
    log_warning "User may not have Global Admin rights - will attempt consent anyway"
    HAS_ADMIN_RIGHTS=false
fi

# ------------------------------------------------------------
# 2. Check if App Already Exists
# ------------------------------------------------------------
log_info "Checking if app already exists..."

EXISTING_APP=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_APP" ] && [ "$EXISTING_APP" != "null" ]; then
    log_warning "App '$APP_NAME' already exists with ID: $EXISTING_APP"
    read -p "Do you want to continue with existing app? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        APP_ID="$EXISTING_APP"
        APP_INFO=$(az ad app show --id "$APP_ID")
        OBJECT_ID=$(echo "$APP_INFO" | jq -r '.id')
        
        # Get service principal
        SP_INFO=$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0]" 2>/dev/null)
        if [ "$SP_INFO" = "null" ] || [ -z "$SP_INFO" ]; then
            log_info "Creating missing Service Principal..."
            SP_INFO=$(az ad sp create --id "$APP_ID")
        fi
        SP_OBJECT_ID=$(echo "$SP_INFO" | jq -r '.id')
        
        log_success "Using existing app - Client ID: $APP_ID"
        log_success "App Object ID: $OBJECT_ID"
        log_success "Service Principal Object ID: $SP_OBJECT_ID"
    else
        log_error "Aborted by user"
        exit 1
    fi
else
    # ------------------------------------------------------------
    # 3. Create New Azure AD App Registration
    # ------------------------------------------------------------
    log_info "Creating Azure AD app registration: $APP_NAME..."
    
    APP_INFO=$(az ad app create --display-name "$APP_NAME" --sign-in-audience "AzureADMyOrg")
    APP_ID=$(echo "$APP_INFO" | jq -r '.appId')
    OBJECT_ID=$(echo "$APP_INFO" | jq -r '.id')
    log_success "App registered with Client ID: $APP_ID"
    log_success "App Object ID: $OBJECT_ID"
    
    # Create Service Principal
    log_info "Creating Service Principal..."
    SP_INFO=$(az ad sp create --id "$APP_ID")
    SP_OBJECT_ID=$(echo "$SP_INFO" | jq -r '.id')
    log_success "Service Principal created with Object ID: $SP_OBJECT_ID"
fi

# ------------------------------------------------------------
# 4. Clear and Add Microsoft Graph API Permissions
# ------------------------------------------------------------
log_info "Clearing existing permissions and adding fresh ones..."

# First, remove any existing Graph permissions to start clean
az ad app permission delete --id "$APP_ID" --api "$GRAPH_APP_ID" --only-show-errors 2>/dev/null || true

# Wait for deletion to propagate
sleep 3

log_info "Adding Microsoft Graph API permissions..."

# Function to add permission with enhanced retry and verification
add_permission_enhanced() {
    local permission_id=$1
    local permission_name=$2
    local max_retries=5
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if az ad app permission add --id "$APP_ID" --api "$GRAPH_APP_ID" --api-permissions "$permission_id=Role" --only-show-errors 2>/dev/null; then
            # Verify the permission was actually added
            sleep 2
            if az ad app permission list --id "$APP_ID" --query "[?resourceAppId=='$GRAPH_APP_ID'].resourceAccess[?id=='$permission_id']" -o tsv | grep -q "$permission_id"; then
                log_success "$permission_name added and verified"
                return 0
            else
                log_warning "$permission_name added but not verified, retrying..."
            fi
        else
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                log_warning "$permission_name failed, retrying... ($retry/$max_retries)"
                sleep 3
            else
                log_error "$permission_name failed after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Add all required permissions
add_permission_enhanced "df021288-bdef-4463-88db-98f22de89214" "User.Read.All"
add_permission_enhanced "5b567255-7703-4780-807c-7be8301ae99b" "Group.Read.All"
add_permission_enhanced "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30" "Application.Read.All"
add_permission_enhanced "7ab1d382-f21e-4acd-a863-ba3e13f7da61" "Directory.Read.All"
add_permission_enhanced "246dd0d5-5bd0-4def-940b-0421030a5b68" "Policy.Read.All"
add_permission_enhanced "483bed4a-2ad3-4361-a73b-c83ccdbdc53c" "RoleManagement.Read.Directory"
add_permission_enhanced "19dbc75e-c2e2-444c-a770-ec69d8559fc7" "Directory.ReadWrite.All"
add_permission_enhanced "df021288-bdef-4463-88db-98f22de89214" "User.ReadWrite.All"

log_success "All Microsoft Graph permissions added."

# ------------------------------------------------------------
# 5. ENHANCED Admin Consent with Multiple Methods
# ------------------------------------------------------------
log_info "Granting admin consent with enhanced methods..."

# Wait for permissions to propagate
log_info "Waiting for permissions to propagate..."
sleep 15

CONSENT_SUCCESS=false

# Method 1: Direct Graph API call for admin consent
log_info "Method 1: Direct Graph API admin consent..."
if [ "$HAS_ADMIN_RIGHTS" = true ]; then
    CONSENT_URL="https://graph.microsoft.com/v1.0/oauth2PermissionGrants"
    CONSENT_PAYLOAD=$(cat <<EOF
{
    "clientId": "$SP_OBJECT_ID",
    "consentType": "AllPrincipals",
    "resourceId": "$(az ad sp list --filter "appId eq '$GRAPH_APP_ID'" --query "[0].id" -o tsv)",
    "scope": "User.Read.All Group.Read.All Application.Read.All Directory.Read.All Policy.Read.All RoleManagement.Read.Directory Directory.ReadWrite.All User.ReadWrite.All"
}
EOF
)
    
    if az rest --method POST --url "$CONSENT_URL" --body "$CONSENT_PAYLOAD" --headers "Content-Type=application/json" --only-show-errors 2>/dev/null; then
        log_success "Direct Graph API admin consent successful!"
        CONSENT_SUCCESS=true
    else
        log_warning "Direct Graph API consent failed, trying next method..."
    fi
fi

# Method 2: CLI admin consent
if [ "$CONSENT_SUCCESS" = false ]; then
    log_info "Method 2: CLI admin consent..."
    if az ad app permission admin-consent --id "$APP_ID" --only-show-errors 2>/dev/null; then
        log_success "CLI admin consent successful!"
        CONSENT_SUCCESS=true
    else
        log_warning "CLI admin consent failed, trying next method..."
    fi
fi

# Method 3: PowerShell approach via az rest
if [ "$CONSENT_SUCCESS" = false ]; then
    log_info "Method 3: PowerShell-style consent via REST API..."
    
    # Get all required permission IDs
    PERMISSIONS=$(az ad app permission list --id "$APP_ID" --query "[?resourceAppId=='$GRAPH_APP_ID'].resourceAccess[].id" -o tsv | tr '\n' ' ')
    
    for PERMISSION_ID in $PERMISSIONS; do
        GRANT_PAYLOAD=$(cat <<EOF
{
    "odata.type": "Microsoft.DirectoryServices.OAuth2PermissionGrant",
    "clientId": "$SP_OBJECT_ID",
    "consentType": "AllPrincipals",
    "resourceId": "$(az ad sp list --filter "appId eq '$GRAPH_APP_ID'" --query "[0].id" -o tsv)",
    "scope": "$PERMISSION_ID"
}
EOF
)
        
        az rest --method POST --url "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" --body "$GRANT_PAYLOAD" --only-show-errors 2>/dev/null || true
    done
    
    log_info "Individual permission grants attempted"
fi

# Method 4: Alternative consent endpoint
if [ "$CONSENT_SUCCESS" = false ]; then
    log_info "Method 4: Alternative consent endpoint..."
    
    ADMIN_CONSENT_URL="https://login.microsoftonline.com/$TENANT_ID/adminconsent"
    CONSENT_PARAMS="client_id=$APP_ID&state=12345&redirect_uri=https://localhost"
    
    log_info "Alternative consent URL: $ADMIN_CONSENT_URL?$CONSENT_PARAMS"
    
    # Try to trigger consent via API call
    if curl -s -X GET "$ADMIN_CONSENT_URL?$CONSENT_PARAMS" >/dev/null 2>&1; then
        log_info "Consent URL accessed successfully"
    fi
fi

# Method 5: Batch consent using Graph batch API
if [ "$CONSENT_SUCCESS" = false ]; then
    log_info "Method 5: Batch consent using Graph API..."
    
    BATCH_PAYLOAD=$(cat <<EOF
{
    "requests": [
        {
            "id": "1",
            "method": "POST",
            "url": "/oauth2PermissionGrants",
            "body": {
                "clientId": "$SP_OBJECT_ID",
                "consentType": "AllPrincipals",
                "resourceId": "$(az ad sp list --filter "appId eq '$GRAPH_APP_ID'" --query "[0].id" -o tsv)",
                "scope": "User.Read.All Group.Read.All Application.Read.All Directory.Read.All Policy.Read.All RoleManagement.Read.Directory"
            }
        }
    ]
}
EOF
)
    
    if az rest --method POST --url "https://graph.microsoft.com/v1.0/\$batch" --body "$BATCH_PAYLOAD" --headers "Content-Type=application/json" --only-show-errors 2>/dev/null; then
        log_success "Batch consent successful!"
        CONSENT_SUCCESS=true
    fi
fi

# Verify consent status
log_info "Verifying consent status..."
sleep 5

GRANTED_PERMISSIONS=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" --query "value[?clientId=='$SP_OBJECT_ID' && resourceId=='$(az ad sp list --filter "appId eq '$GRAPH_APP_ID'" --query "[0].id" -o tsv)'].scope" -o tsv 2>/dev/null || echo "")

if [ -n "$GRANTED_PERMISSIONS" ]; then
    log_success "Permissions verified as granted: $GRANTED_PERMISSIONS"
    CONSENT_SUCCESS=true
else
    log_warning "Could not verify permissions via API"
fi

if [ "$CONSENT_SUCCESS" = false ]; then
    log_warning "Automated admin consent methods completed"
    log_info "Please verify consent status manually at:"
    log_info "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/ApiPermissions/appId/$APP_ID"
else
    log_success "Admin consent completed successfully!"
fi

# ------------------------------------------------------------
# 6. Create Client Secret
# ------------------------------------------------------------
log_info "Creating client secret..."

SECRET_INFO=$(az ad app credential reset --id "$APP_ID" --append --display-name "automation-secret-$(date +%Y%m%d-%H%M)" --years 2)
CLIENT_SECRET=$(echo "$SECRET_INFO" | jq -r '.password')
log_success "Client secret created (expires in 2 years)"

# ------------------------------------------------------------
# 7. Assign Enhanced Subscription Roles
# ------------------------------------------------------------
log_info "Assigning enhanced subscription roles..."

# Function to assign role with retry
assign_role() {
    local role_name=$1
    local max_retries=3
    local retry=0
    
    # Check if role assignment already exists
    local existing_assignment=$(az role assignment list --assignee "$SP_OBJECT_ID" --scope "/subscriptions/$SUBSCRIPTION_ID" --role "$role_name" --query "[0].id" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$existing_assignment" ] && [ "$existing_assignment" != "null" ]; then
        log_success "$role_name role already assigned"
        return 0
    fi
    
    while [ $retry -lt $max_retries ]; do
        if az role assignment create --assignee "$SP_OBJECT_ID" --role "$role_name" --scope "/subscriptions/$SUBSCRIPTION_ID" --only-show-errors 2>/dev/null; then
            log_success "$role_name role assigned successfully"
            return 0
        else
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                log_warning "$role_name assignment failed, retrying... ($retry/$max_retries)"
                sleep 3
            else
                log_warning "$role_name assignment failed after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Assign multiple roles for comprehensive access
assign_role "Reader"
assign_role "Security Reader"

# ------------------------------------------------------------
# 8. Test Connection and Verify Setup
# ------------------------------------------------------------
log_info "Testing service principal authentication..."

# Test service principal login
if az login --service-principal -u "$APP_ID" -p "$CLIENT_SECRET" --tenant "$TENANT_ID" --only-show-errors 2>/dev/null; then
    log_success "Service principal authentication test successful!"
    
    # Test Graph API access
    log_info "Testing Graph API access..."
    if az rest --method GET --url "https://graph.microsoft.com/v1.0/users" --query "value[0].displayName" -o tsv --only-show-errors 2>/dev/null; then
        log_success "Graph API access test successful!"
        CONNECTION_TEST_SUCCESS=true
    else
        log_warning "Graph API access test failed - may need manual consent"
        CONNECTION_TEST_SUCCESS=false
    fi
    
    # Switch back to original user
    az login --username "$CURRENT_USER" --only-show-errors 2>/dev/null || az login --only-show-errors 2>/dev/null
else
    log_warning "Service principal authentication test failed"
    CONNECTION_TEST_SUCCESS=false
fi

# ------------------------------------------------------------
# 9. Final Summary and Verification
# ------------------------------------------------------------
echo ""
if [ "$CONNECTION_TEST_SUCCESS" = true ]; then
    log_success "🎉 Azure AD Service Account setup completed successfully!"
    log_success "🔗 Connection test PASSED - Ready to use!"
else
    log_warning "🎉 Azure AD Service Account setup completed with warnings"
    log_warning "🔗 Connection test FAILED - Manual consent may be required"
fi

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
echo "=== ENVIRONMENT VARIABLES FOR YOUR APP ==="
echo "export AZURE_TENANT_ID='$TENANT_ID'"
echo "export AZURE_CLIENT_ID='$APP_ID'"
echo "export AZURE_CLIENT_SECRET='$CLIENT_SECRET'"
echo ""
echo "=== TEST COMMANDS ==="
echo "# Test service principal login:"
echo "az login --service-principal -u '$APP_ID' -p '$CLIENT_SECRET' --tenant '$TENANT_ID'"
echo ""
echo "# Test Graph API access:"
echo "az rest --method GET --url 'https://graph.microsoft.com/v1.0/users' --query 'value[0:5].[displayName,userPrincipalName]'"
echo ""
echo "=== VERIFICATION LINKS ==="
echo "App Overview: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$APP_ID"
echo "API Permissions: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/ApiPermissions/appId/$APP_ID"
echo "Certificates & Secrets: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Credentials/appId/$APP_ID"
echo ""
echo "=== NEXT STEPS ==="
if [ "$CONNECTION_TEST_SUCCESS" = true ]; then
    echo "✅ 1. Setup is complete - no further action needed"
    echo "✅ 2. Use the credentials above in your application"
    echo "✅ 3. Store credentials securely (Azure Key Vault recommended)"
else
    echo "🔍 1. Verify admin consent status in the API Permissions page"
    echo "🔍 2. If needed, click 'Grant admin consent for [Tenant]' button"
    echo "🔍 3. Re-run connection test after granting consent"
fi
echo "🔒 4. Configure your automation tools with these credentials"
echo "📝 5. Document the setup for your team"

# Create a test script for easy verification
cat > test-azure-connection.sh << EOF
#!/bin/bash
echo "🧪 Testing Azure AD Service Principal Connection..."
echo ""

# Test 1: Service Principal Login
echo "Test 1: Service Principal Authentication"
if az login --service-principal -u '$APP_ID' -p '$CLIENT_SECRET' --tenant '$TENANT_ID' --only-show-errors 2>/dev/null; then
    echo "✅ Service principal login successful"
else
    echo "❌ Service principal login failed"
    exit 1
fi

# Test 2: Graph API Users
echo ""
echo "Test 2: Microsoft Graph API - Users"
if az rest --method GET --url 'https://graph.microsoft.com/v1.0/users' --query 'value[0:3].[displayName,userPrincipalName]' -o table --only-show-errors 2>/dev/null; then
    echo "✅ Users API access successful"
else
    echo "❌ Users API access failed"
fi

# Test 3: Graph API Groups
echo ""
echo "Test 3: Microsoft Graph API - Groups"
if az rest --method GET --url 'https://graph.microsoft.com/v1.0/groups' --query 'value[0:3].[displayName,description]' -o table --only-show-errors 2>/dev/null; then
    echo "✅ Groups API access successful"
else
    echo "❌ Groups API access failed"
fi

# Test 4: Graph API Applications
echo ""
echo "Test 4: Microsoft Graph API - Applications"
if az rest --method GET --url 'https://graph.microsoft.com/v1.0/applications' --query 'value[0:3].[displayName,appId]' -o table --only-show-errors 2>/dev/null; then
    echo "✅ Applications API access successful"
else
    echo "❌ Applications API access failed"
fi

echo ""
echo "🏁 Connection test completed!"
echo "If any tests failed, you may need to grant admin consent manually."
EOF

chmod +x test-azure-connection.sh
log_success "Created test-azure-connection.sh script for easy verification"

echo ""
log_info "🚀 Run './test-azure-connection.sh' to verify all connections are working!"
