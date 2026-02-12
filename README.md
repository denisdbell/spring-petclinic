# 🧪 Lab: End-to-End Azure DevOps Pipeline for Spring Petclinic

## 🎯 Objective

In this lab, you will manually provision infrastructure, secure the
connection between Azure DevOps and Azure, import repositories, and
build a Build Once, Deploy Many pipeline.

## 📌 Note on Scripts

The helper scripts (`petclinic-infra.sh`,
`petclinic-service-connection.sh`) and the ARM template
(`petclinic-infra.json`) are located in the spring-petclinic repository.

You will not execute these scripts as full files. Instead, you will run
the individual commands inside them.

## ✅ Prerequisites

-   Azure Subscription (Owner or User Access Administrator)
-   Azure DevOps Organization
-   Azure Cloud Shell (Bash)

## 🧩 Step 1: Import Repositories

### Application Repo

Clone URL: https://github.com/denisdbell/spring-petclinic\
Name: spring-petclinic

### Template Repo

Clone URL: https://github.com/denisdbell/petclinic-pipeline-template\
Name: petclinic-pipeline-template

## ☁️ Step 2: Create Azure Infrastructure

### Set Location

``` bash
LOC="westus3"
```

### Dev

``` bash
az group create --name rg-dev --location $LOC
az deployment group create   --name DeployDev   --resource-group rg-dev   --template-file petclinic-infra.json   --parameters environmentName=dev
```

### Test

``` bash
az group create --name rg-testing --location $LOC
az deployment group create   --name DeployTest   --resource-group rg-testing   --template-file petclinic-infra.json   --parameters environmentName=testing
```

### Prod

``` bash
az group create --name rg-prod --location $LOC
az deployment group create   --name DeployProd   --resource-group rg-prod   --template-file petclinic-infra.json   --parameters environmentName=prod
```

## 🔐 Step 3: Service Connection

Create Azure-Subscription-Conn using automatic service principal.

### Assign Roles

``` bash
SP_ID="<CLIENT_ID>"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az role assignment create   --assignee $SP_ID   --role "Contributor"   --scope "/subscriptions/$SUBSCRIPTION_ID"

az role assignment create   --assignee $SP_ID   --role "User Access Administrator"   --scope "/subscriptions/$SUBSCRIPTION_ID"
```

## ⚙️ Step 4: Pipeline Structure

-   build.yaml: Builds and publishes artifacts
-   deploy.yaml: Deploys to Azure App Service

Pipeline Flow: Build → Dev → Approval → Test → Approval → Prod

## 🚀 Step 5: Run Pipeline

Update `azure-pipeline.yaml` variables:

``` yaml
variables:
  azureServiceConnection: 'Azure-Subscription-Conn'
  devAppName: 'app-petclinic-dev-xxx'
  testAppName: 'app-petclinic-testing-xxx'
  prodAppName: 'app-petclinic-prod-xxx'
```

Run from Azure DevOps → Pipelines.

## ✅ Step 6: Validation

Open Production URL → Click Veterinarians → Verify list loads.

## 🎉 Complete

You now have a secure multi-stage Azure DevOps pipeline.
