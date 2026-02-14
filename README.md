# Lab: End-to-End Azure DevOps Pipeline for Spring Petclinic

## Objective

In this lab, you will manually provision infrastructure, secure the connection between Azure DevOps and Azure, import repositories, and build a "Build Once, Deploy Many" pipeline.

> **Note on Scripts:** The helper scripts (`petclinic-infra.sh`, `petclinic-service-connection.sh`) and the ARM template (`petclinic-infra.json`) are located in the `spring-petclinic` repository. You will not execute these scripts as whole files. Instead, you will execute the specific commands inside them individually to understand each step of the provisioning process.

---

## Prerequisites

- **Azure Subscription:** Owner or User Access Administrator role
- **Azure DevOps Organization:** With a Project created (e.g., `PetClinic`)
- **Azure CLI:** Open the Azure Cloud Shell (Bash) in the Azure Portal

---

## Step 1: Import Repositories

We will start by importing the source code and templates into your Azure DevOps project.

### 1. Import the Application

1. Navigate to **Azure DevOps > Repos**
2. Click the repo dropdown (top center) > **Import repository**
3. Enter the following details:
   - **Clone URL:** `https://github.com/denisdbell/spring-petclinic`
   - **Name:** `spring-petclinic`
4. Click **Import**

### 2. Import the Templates

1. Click the repo dropdown > **Import repository**
2. Enter the following details:
   - **Clone URL:** `https://github.com/denisdbell/petclinic-pipeline-template`
   - **Name:** `petclinic-pipeline-template`
3. Click **Import**

---

## Step 2: Create Azure Infrastructure

**Reference File:** `spring-petclinic/petclinic-infra.sh`

We will manually run the commands to provision the dev, testing, and prod environments.

**Action:** Copy and paste the following commands into your Azure Cloud Shell one by one.

### 1. Set Up Variables

First, ensure you have the ARM template file available in Cloud Shell. You can upload `petclinic-infra.json` from the repo or create it. Then, set your location.

```bash
# Upload or ensure petclinic-infra.json is in your current directory
# Set the target region (e.g., westus3 or eastus2 to avoid quotas)
LOC="westus3"
```

### 2. Provision Development (Dev)

Create the resource group and deploy the App Service + Database.

```bash
# Create Resource Group
az group create --name rg-dev --location $LOC

# Deploy Resources
az deployment group create \
  --name DeployDev \
  --resource-group rg-dev \
  --template-file petclinic-infra.json \
  --parameters environmentName=dev
```

### 3. Provision Testing (Test)

Repeat the process for the testing environment.

```bash
# Create Resource Group
az group create --name rg-testing --location $LOC

# Deploy Resources
az deployment group create \
  --name DeployTest \
  --resource-group rg-testing \
  --template-file petclinic-infra.json \
  --parameters environmentName=testing
```

### 4. Provision Production (Prod)

Finally, create the production environment.

```bash
# Create Resource Group
az group create --name rg-prod --location $LOC

# Deploy Resources
az deployment group create \
  --name DeployProd \
  --resource-group rg-prod \
  --template-file petclinic-infra.json \
  --parameters environmentName=prod
```

**Checkpoint:** Verify in the Azure Portal that `rg-dev`, `rg-testing`, and `rg-prod` exist and contain resources.

---

## Step 3: Configure Service Connection & Roles

**Reference File:** `spring-petclinic/petclinic-service-connection.sh`

You need to authorize Azure DevOps to deploy to your subscription and assign the correct RBAC roles.

### 1. Create the Connection

1. Go to **Azure DevOps > Project Settings > Service connections**
2. Click **New service connection > Azure Resource Manager > Service principal (automatic)**
3. Select your **Subscription**
4. **Service Connection Name:** `Azure-Subscription-Conn`
5. **Grant access permission to all pipelines:** Checked
6. Click **Save**

### 2. Assign Roles (Command Line)

The Service Connection created a "Service Principal" (Identity) in Azure. You must now grant that identity permission to manage resources.

**Get the Service Principal ID:**

1. Go to the Service Connection you just created in Azure DevOps
2. Click **Manage Service Principal** (link opens Azure Portal)
3. Copy the **Application (client) ID**

**Run these commands in Cloud Shell:**

```bash
# REPLACE with the Client ID you just copied
SP_ID="<PASTE_YOUR_CLIENT_ID_HERE>"

# Get your Subscription ID automatically
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "Using Service Principal: $SP_ID"

# 1. Assign CONTRIBUTOR Role
# Required to create/update App Services and Databases
az role assignment create \
  --assignee $SP_ID \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# 2. Assign USER ACCESS ADMINISTRATOR Role
# Required if the pipeline needs to assign permissions to other resources later
az role assignment create \
  --assignee $SP_ID \
  --role "User Access Administrator" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

---

## Step 4: Understand the Pipeline Templates

Before running the pipeline, let's understand how the repositories work together.

### 1. The Template Repo (petclinic-pipeline-template)

This repository contains the "Logic" that is shared across environments.

- **build.yaml:** Compiles the Java code using Maven and publishes the Artifact (drop)
- **deploy.yaml:** Downloads the Artifact and deploys it to Azure App Service. It accepts parameters like `webAppName` and `environmentName`, making it reusable for Dev, Test, and Prod

### 2. The Application Pipeline (spring-petclinic/azure-pipeline.yaml)

This is the "Orchestrator". It triggers on code changes and calls the templates.

- **Resources Section:** It links to the `petclinic-pipeline-template` repo so it can use the YAML files inside it
- **Stages:** It defines the workflow: Build → DeployDev → ApproveTesting → DeployTest, etc.

---

## Step 5: Configure and Run the Pipeline

### 1. Update azure-pipeline.yaml

You must update the pipeline to use your specific resource names.

1. In Azure DevOps, go to **Repos > spring-petclinic**
2. Edit `azure-pipeline.yaml`
3. **Update the Repository Reference:**

```yaml
resources:
  repositories:
    - repository: templates
      type: git
      name: <YOUR_PROJECT_NAME>/petclinic-pipeline-template # e.g. PetClinic/petclinic-pipeline-template
      ref: main
```

4. **Update Variables:** Replace the placeholder names with the actual App Service names you created in Step 2 (check Azure Portal)

```yaml
variables:
  azureServiceConnection: 'Azure-Subscription-Conn'
  devAppName: 'app-petclinic-dev-<YOUR_SUFFIX>'
  testAppName: 'app-petclinic-testing-<YOUR_SUFFIX>'
  prodAppName: 'app-petclinic-prod-<YOUR_SUFFIX>'
```

5. Commit the changes

### 2. Create and Run

1. Go to **Pipelines > New Pipeline**
2. Select **Azure Repos Git > spring-petclinic**
3. Select **Existing Azure Pipelines YAML file**
4. **Path:** `/azure-pipeline.yaml`
5. Click **Run**

### 3. Grant Permissions

The pipeline will pause almost immediately.

**Why?** It needs permission to use the Service Connection `Azure-Subscription-Conn`.

**Action:** Click the "Permission Needed" message on the run screen, then click **Permit** (twice).

### 4. Manual Approvals

The pipeline is designed to pause between environments.

- When **DeployDev** finishes, the pipeline will pause at **ApproveTesting**
- Click **Review and Approve** to proceed to the Testing environment
- Repeat this process for Production

---

## Step 6: Validation

Once the pipeline completes **DeployProd:**

1. Navigate to the Production App Service URL in your browser
2. Click **"Veterinarians"**
3. Verify that a list of veterinarians loads, confirming the application is successfully connected to the Database

---

## Summary

You have successfully:

✅ Imported repositories into Azure DevOps  
✅ Provisioned infrastructure across three environments (Dev, Testing, Prod)  
✅ Configured secure service connections with proper RBAC roles  
✅ Built and executed a "Build Once, Deploy Many" CI/CD pipeline  
✅ Validated the deployed application
