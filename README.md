# 🚀 Spring PetClinic: Azure DevOps Pipeline with SonarQube Analysis

This project automates the deployment of the Spring PetClinic application to Azure using a multi-stage DevOps pipeline. It features **SonarQube Static Code Analysis** and a "Build Once, Promote Many" strategy, where Docker images are moved from **Development** → **Testing** → **Production** Azure Container Registries (ACR) upon passing manual approval gates.

## 📋 Prerequisites

* **Azure Subscription**: Access to create Resource Groups and assign RBAC roles.
* **Azure DevOps Organization**: Permissions to create Projects, Pipelines, and Service Connections.
* **Azure Portal Access**: Ability to use Cloud Shell or deploy custom templates.

---

## 🛠️ Step 1: Import Repositories

You must import the following two repositories into your Azure DevOps Project to establish the codebase and pipeline logic. **⚠️ CRITICAL:** You must use the **`master-acr-sonar-cloud`** branch for **BOTH** repositories.

### 1. Application Repository (Source Code & Main Pipeline)

* **Import URL**: `https://github.com/denisdbell/spring-petclinic`
* **Branch Requirement**: Ensure the default branch is set to **`master-acr-sonar-cloud`**.
* **Description**: Contains the Java source code and the primary `azure-pipeline.yaml` definition.

### 2. Template Repository (Pipeline Logic)

* **Import URL**: `https://github.com/denisdbell/petclinic-pipeline-template`
* **Branch Requirement**: Ensure the default branch is set to **`master-acr-sonar-cloud`**.
* **Reasoning**: The main pipeline explicitly references this branch to load the deployment templates:

```yaml
resources:
  repositories:
    - repository: templates
      type: git
      name: Petclinic/petclinic-pipeline-template
      ref: master-acr-sonar-cloud
```

---

## 🏗️ Step 2: Provision Azure Infrastructure

You can provision the entire infrastructure (Resource Groups, ACRs, App Services, Databases, and SonarQube) using **Azure Cloud Shell** or the **Deploy to Azure** button.

### Option A: Deploy via Azure Portal (Recommended)

Click the button below to automatically load the template into the Azure Portal. This allows you to configure parameters via the UI and deploy without writing code.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fdenisdbell%2Fspring-petclinic%2Frefs%2Fheads%2Fmaster-acr-sonar-cloud%2Fpetclinic-infra.json)

### Option B: Deploy via Azure Cloud Shell

1. Log in to the [Azure Portal](https://portal.azure.com) and click the **Cloud Shell** icon (terminal) in the top toolbar.
2. Select **Bash** as the environment.
3. **Upload Files**: Use the "Upload/Download files" button in the Cloud Shell toolbar to upload `petclinic-infra.json` and `petclinic-infra.sh`.
4. **Execute the Script**:

```bash
# Make the script executable
chmod +x petclinic-infra.sh

# Run the deployment (defaults to westus3)
./petclinic-infra.sh
```

### 🔍 What Gets Deployed?

Regardless of the method chosen, the following resources will be created:

| Resource | Details |
| :--- | :--- |
| **Resource Groups** | `rg-petclinic-dev`, `rg-petclinic-testing`, `rg-petclinic-prod`, `rg-sonarqube` |
| **Container Registries** | Three distinct ACRs (Dev, Test, Prod) |
| **App Services** | Three Web Apps for Containers (Dev, Test, Prod) |
| **Databases** | Three Azure Database for PostgreSQL Flexible Servers |
| **SonarQube** | A dedicated App Service hosting SonarQube Community Edition |

---

## ⚙️ Step 3: Configure Azure DevOps Service Connections

The pipeline requires specific Service Connections to authorize actions against your Azure resources. Navigate to **Project Settings** → **Service connections** and create the following:

| Connection Name | Type | Target Resource |
| :--- | :--- | :--- |
| **Azure-Subscription-Conn** | Azure Resource Manager | Your Azure Subscription |
| **dev-acr-service-connection** | Docker Registry | The **Dev** ACR created in Step 2 |
| **test-acr-service-connection** | Docker Registry | The **Testing** ACR created in Step 2 |
| **prod-acr-service-connection** | Docker Registry | The **Production** ACR created in Step 2 |
| **sonarqube-service-connection** | SonarQube | The SonarQube App Service URL & Token |

> **Note**: To configure SonarQube, access the deployed App Service URL (e.g., `https://sonar-petclinic-xyz.azurewebsites.net`), generate a token in the security settings, and create a project with the key `petclinic`.

---

## 📝 Step 4: Update Pipeline Variables

The infrastructure script generates resources with **unique suffixes** (e.g., `acrpetclinicdevX1Y2`) to ensure global uniqueness. You must update the pipeline variables to match these generated names.

1. Open `azure-pipeline.yaml` in the **spring-petclinic** repo.
2. Update the `variables` section:

```yaml
variables:
  # App Service Names (Check Azure Portal for exact names)
  devAppName: 'app-petclinic-dev-<YOUR_SUFFIX>'
  testAppName: 'app-petclinic-testing-<YOUR_SUFFIX>'
  prodAppName: 'app-petclinic-prod-<YOUR_SUFFIX>'

  # ACR Login Servers
  devAcrLoginServer: 'acrpetclinicdev<YOUR_SUFFIX>.azurecr.io'
  testAcrLoginServer: 'acrpetclinictesting<YOUR_SUFFIX>.azurecr.io'
  prodAcrLoginServer: 'acrpetclinicprod<YOUR_SUFFIX>.azurecr.io'
```

---

## ▶️ Step 5: Run the Pipeline

1. In Azure DevOps, go to **Pipelines** → **New Pipeline**.
2. Select **Azure Repos Git** → `spring-petclinic`.
3. Select **Existing Azure Pipelines YAML file** → `/azure-pipeline.yaml`.
4. Run the pipeline.

---

## 🔄 Pipeline Workflow

**Build Stage** — Compiles Java code, runs SonarQube analysis, builds the Docker image, and pushes it to the Dev ACR.

**Deploy Dev** — Deploys the container from Dev ACR to the Dev Web App.

**Manual Approval** — Pauses for validation before promoting to Testing.

**Deploy Testing**
- *Promote*: Pulls image from Dev ACR, retags it, and pushes to Test ACR.
- *Deploy*: Updates the Test Web App.

**Manual Approval** — Pauses for validation before promoting to Production.

**Deploy Prod**
- *Promote*: Pulls image from Test ACR, retags it, and pushes to Prod ACR.
- *Deploy*: Updates the Production Web App.
