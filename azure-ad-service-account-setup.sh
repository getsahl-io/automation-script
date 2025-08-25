#!/bin/bash

# Extra Microsoft Graph API permissions for the Service Principal
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"  # Microsoft Graph App ID

echo "🔧 Adding Microsoft Graph API permissions..."

# User.Read.All
az ad app permission add \
  --id $CLIENT_ID \
  --api $GRAPH_APP_ID \
  --api-permissions "df021288-bdef-4463-88db-98f22de89214=Role"

# Group.Read.All
az ad app permission add \
  --id $CLIENT_ID \
  --api $GRAPH_APP_ID \
  --api-permissions "5b567255-7703-4780-807c-7be8301ae99b=Role"

# Application.Read.All
az ad app permission add \
  --id $CLIENT_ID \
  --api $GRAPH_APP_ID \
  --api-permissions "e2af2b9e-3a82-44c2-b0c9-9691c07f07d2=Role"

# Directory.Read.All
az ad app permission add \
  --id $CLIENT_ID \
  --api $GRAPH_APP_ID \
  --api-permissions "06da0dbc-49e2-44d2-8312-53f166ab848a=Role"

# Policy.Read.All
az ad app permission add \
  --id $CLIENT_ID \
  --api $GRAPH_APP_ID \
  --api-permissions "246dd0d5-5bd0-4def-940b-0421030a5b68=Role"

# RoleManagement.Read.Directory
az ad app permission add \
  --id $CLIENT_ID \
  --api $GRAPH_APP_ID \
  --api-permissions "9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8=Role"

echo "✅ Microsoft Graph permissions added."

# Grant admin consent (requires Global Admin privileges)
echo "🔑 Granting admin consent..."
az ad app permission grant --id $CLIENT_ID --api $GRAPH_APP_ID --scope "User.Read.All Group.Read.All Application.Read.All Directory.Read.All Policy.Read.All RoleManagement.Read.Directory"
az ad app permission admin-consent --id $CLIENT_ID

echo "🎉 Azure AD Graph permissions granted successfully!"
