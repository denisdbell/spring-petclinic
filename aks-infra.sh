#!/bin/bash
# aks-infra.sh - Run in Azure Cloud Shell

# Variables
LOCATION="westus3"
SUFFIX=$RANDOM # Generates a random suffix for uniqueness
DB_PASSWORD="Replace-Me-StrongPassword-123!"

# Resource Groups
RG_DEV="rg-petclinic-dev"
RG_TEST="rg-petclinic-testing"
RG_PROD="rg-petclinic-prod"
RG_AKS="rg-petclinic-aks"

# Cluster & ACR Names
AKS_NAME="aks-petclinic"
ACR_DEV="acrpetclinicdev$SUFFIX"
ACR_TEST="acrpetclinictest$SUFFIX"
ACR_PROD="acrpetclinicprod$SUFFIX"

echo "Creating Resource Groups..."
az group create --name $RG_DEV --location $LOCATION
az group create --name $RG_TEST --location $LOCATION
az group create --name $RG_PROD --location $LOCATION
az group create --name $RG_AKS --location $LOCATION

echo "Creating Azure Container Registries..."
az acr create -g $RG_DEV -n $ACR_DEV --sku Basic --admin-enabled true
az acr create -g $RG_TEST -n $ACR_TEST --sku Basic --admin-enabled true
az acr create -g $RG_PROD -n $ACR_PROD --sku Basic --admin-enabled true

echo "Creating AKS Cluster (This will take a few minutes)..."
az aks create \
  --resource-group $RG_AKS \
  --name $AKS_NAME \
  --node-count 2 \
  --generate-ssh-keys \
  --network-plugin kubenet

echo "Attaching ACRs to AKS Cluster (Granting AcrPull Roles)..."
az aks update -n $AKS_NAME -g $RG_AKS --attach-acr $ACR_DEV
az aks update -n $AKS_NAME -g $RG_AKS --attach-acr $ACR_TEST
az aks update -n $AKS_NAME -g $RG_AKS --attach-acr $ACR_PROD

echo "Creating Kubernetes Namespaces..."
az aks get-credentials --resource-group $RG_AKS --name $AKS_NAME --admin
kubectl create namespace dev
kubectl create namespace testing
kubectl create namespace prod

echo "Creating PostgreSQL Flexible Servers..."
for ENV in dev testing prod; do
  DB_NAME="db-petclinic-$ENV-$SUFFIX"
  RG_NAME="rg-petclinic-$ENV"
  
  az postgres flexible-server create \
    --resource-group $RG_NAME \
    --name $DB_NAME \
    --location $LOCATION \
    --admin-user "petclinic_admin" \
    --admin-password $DB_PASSWORD \
    --sku-name Standard_B1ms \
    --tier Burstable \
    --version 13 \
    --storage-size 32 \
    --public-access 0.0.0.0 # Allows Azure Services to access the DB
  
  az postgres flexible-server db create \
    --resource-group $RG_NAME \
    --server-name $DB_NAME \
    --database-name petclinic
done

echo "====================================================="
echo "Infrastructure deployed successfully!"
echo "AKS Cluster: $AKS_NAME"
echo "Dev ACR: $ACR_DEV"
echo "Test ACR: $ACR_TEST"
echo "Prod ACR: $ACR_PROD"
echo "====================================================="
