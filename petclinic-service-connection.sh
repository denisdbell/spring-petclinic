# Variables
SP_ID="aaaaa-bbbb-cccc-dddd-eeeee" #Replace with service your connection id
# Automatically get the current subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "Using Subscription ID: $SUBSCRIPTION_ID"

# --- 1. Assign CONTRIBUTOR (Essential) ---
# This allows the pipeline to create Resource Groups, Web Apps, and Databases.
echo "Assigning 'Contributor' role..."
az role assignment create \
  --assignee $SP_ID \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# --- 2. Assign USER ACCESS ADMINISTRATOR (Future-Proofing) ---
# This allows the pipeline to grant permissions to Managed Identities.
# (e.g., If you later want the Web App to read secrets from Key Vault without a password)
echo "Assigning 'User Access Administrator' role..."
az role assignment create \
  --assignee $SP_ID \
  --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

echo "--------------------------------------------------"
echo "Success! Service Principal $SP_ID now has full DevOps permissions."