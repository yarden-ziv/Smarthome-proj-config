#!/bin/bash

GRAFANA_HOST="http://localhost:3000"
ADMIN_USER="admin"
ADMIN_PASS="admin"

# Create the viewer user
echo "Creating Grafana user 'viewer'..."

CREATE_RESPONSE=$(curl -s -X POST "$GRAFANA_HOST/api/admin/users" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  -H "Content-Type: application/json" \
  -d '{
        "name": "Viewer",
        "email": "viewer@example.com",
        "login": "viewer",
        "password": "viewer"
      }')

# Extract the user ID
USER_ID=$(echo "$CREATE_RESPONSE" | grep -oP '"id"\s*:\s*\K\d+')

if [[ -z "$USER_ID" ]]; then
  echo "Failed to create user or extract user ID. Response:"
  echo "$CREATE_RESPONSE"
  exit 1
fi

echo "User 'viewer' created with ID $USER_ID."

# Assign Viewer role to the user in org ID 1
echo "Assigning 'Viewer' role..."

ROLE_RESPONSE=$(curl -s -X PATCH "$GRAFANA_HOST/api/orgs/1/users/$USER_ID" \
  -u "$ADMIN_USER:$ADMIN_PASS" \
  -H "Content-Type: application/json" \
  -d '{"role": "Viewer"}')

if echo "$ROLE_RESPONSE" | grep -q '"message":"User role updated"'; then
  echo "Viewer role successfully assigned."
else
  echo "Failed to assign role. Response:"
  echo "$ROLE_RESPONSE"
  exit 1
fi
