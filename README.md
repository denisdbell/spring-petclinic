# Petclinic — Azure AKS Deployment Guide

This guide walks you through deploying the Spring Petclinic application to Azure Kubernetes Service (AKS) using a multi-environment CI/CD pipeline built on Azure DevOps.

---

## Architecture Overview

The setup provisions three isolated environments (Dev, Testing, Prod), each with its own Azure Container Registry (ACR) and PostgreSQL Flexible Server, all sharing a single AKS cluster.

```
Azure Subscription
├── rg-petclinic-aks        → AKS Cluster (aks-petclinic)
├── rg-petclinic-dev        → ACR (dev) + PostgreSQL (dev)
├── rg-petclinic-testing    → ACR (test) + PostgreSQL (test)
└── rg-petclinic-prod       → ACR (prod) + PostgreSQL (prod)
```

**Pipeline flow:**

```
[Code Push] → Build & Test → Deploy Dev → [Manual Approval]
           → Deploy Testing → [Manual Approval] → Deploy Prod
```

Images are built once in Dev and **promoted** (pull → retag → push) to Testing and Prod ACRs rather than rebuilt, ensuring environment parity.

---

## Prerequisites

Before you begin, ensure you have the following installed and configured:

- **Azure CLI** — [Install guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- **kubectl** — [Install guide](https://kubernetes.io/docs/tasks/tools/)
- An active **Azure Subscription** with permissions to create resource groups, AKS clusters, ACRs, and PostgreSQL servers at the subscription level
- An **Azure DevOps** organization and project
- The application repository containing a `Dockerfile`, `pom.xml`, and `k8s/manifest.yaml`

---

## Step 1 — Provision Azure Infrastructure

### 1.1 Generate an SSH Key Pair

The AKS nodes require an SSH public key for Linux node access.

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/aks_rsa -N ""
```

### 1.2 Deploy the ARM Template

Run the following command to deploy all infrastructure in one shot. Replace the password with a strong value of your own.

```bash
az deployment sub create \
  --name petclinic-aks-deploy \
  --location westus3 \
  --template-file aks-infra.json \
  --parameters sshRSAPublicKey="$(cat ~/.ssh/aks_rsa.pub)" \
  --parameters dbAdminPassword="<YOUR-STRONG-PASSWORD>" \
  --parameters region="westus3"
```

> **Note:** The deployment runs at the **subscription** scope and creates all four resource groups automatically. It may take 10–15 minutes to complete.

### 1.3 Retrieve the Unique Suffix --THIS SHOULD BE FIX DOES NOT RETURN THE SUFFIX

The ARM template generates a 6-character unique suffix to make globally unique resource names. Retrieve it after deployment:

```bash
az deployment sub show \
  --name petclinic-aks-deploy \
  --query "properties.outputs" \
  --output json
```

Note the value of `acrDevName` — the last 6 characters are your unique suffix (e.g., `acrpetclinicdev**a1b2c3**`). You will need this in Step 3.

### 1.4 Resources Created

| Resource | Name Pattern | Environment |
|---|---|---|
| AKS Cluster | `aks-petclinic` | Shared |
| Container Registry | `acrpetclinicdev<suffix>` | Dev |
| Container Registry | `acrpetclinictest<suffix>` | Testing |
| Container Registry | `acrpetclinicprod<suffix>` | Prod |
| PostgreSQL Server | `db-petclinic-dev-<suffix>` | Dev |
| PostgreSQL Server | `db-petclinic-testing-<suffix>` | Testing |
| PostgreSQL Server | `db-petclinic-prod-<suffix>` | Prod |

All PostgreSQL servers use version 13, the `Standard_B1ms` (Burstable) SKU, and have a `petclinic` database pre-created. The AKS kubelet identity is automatically granted `AcrPull` on each registry.

---

## Step 2 — Configure Azure DevOps

### 2.1 Create Service Connections

In your Azure DevOps project, go to **Project Settings → Service connections** and create the following:

**Kubernetes Service Connection**

| Field | Value |
|---|---|
| Name | `aks-service-connection` |
| Type | Azure Resource Manager (AKS) |
| Cluster | `aks-petclinic` in `rg-petclinic-aks` |
| Authentication | Select **"Use cluster admin credentials"** |

> **Important:** When creating this connection, expand the authentication options and check **"Use cluster admin credentials"**. Without this, the pipeline agent will use a restricted service account token that lacks the permissions needed to manage namespaces and deploy resources.

**Docker Registry / ACR Service Connections** — create one for each environment:

| Name | ACR |
|---|---|
| `dev-acr-service-connection` | `acrpetclinicdev<suffix>` |
| `test-acr-service-connection` | `acrpetclinictest<suffix>` |
| `prod-acr-service-connection` | `acrpetclinicprod<suffix>` |

For each ACR connection, choose **Docker Registry** → **Azure Container Registry** and select the corresponding registry.


### 2.2 Create Pipeline Environments

Go to **Pipelines → Environments** and create three environments. These are used for deployment tracking and manual approval gates:

- `dev`
- `testing`
- `prod`

For `testing` and `prod`, you may optionally add approval checks under the environment's **Approvals and checks** settings (though the pipeline also uses `ManualValidation` tasks as a fallback).

### 2.3 Import the Pipeline Template Repository

The pipeline references an external template repository. Import or fork your template repo into an Azure DevOps project named `Petclinic` under the repository name `petclinic-pipeline-template`, on a branch named **`master-aks`**. Place `build.yaml`, `deploy.yaml`, and `promote-acr.yaml` in the root of that repository.

> **Important:** The `ref` field in `azure-pipeline.yaml` must point to `master-aks`:
> ```yaml
> resources:
>   repositories:
>     - repository: templates
>       type: git
>       name: Petclinic/petclinic-pipeline-template
>       ref: master-aks
> ```

### 2.4 Create a Secret Pipeline Variable

Rather than storing the database password in plain text in the YAML, set it as a secret variable:

1. Open your pipeline and click **Edit → Variables**
2. Add a variable named `dbAdminPassword` with the same password used during ARM deployment
3. Check the **Keep this value secret** option

Then update `azure-pipeline.yaml` to reference `$(dbAdminPassword)` and remove the hardcoded value.

---

## Step 3 — Configure the Pipeline YAML

Open `azure-pipeline.yaml` and update these two values:

```yaml
# UPDATE: Replace 'a1b2c3' with your actual 6-character suffix from Step 1.3
uniqueSuffix: 'a1b2c3'

# SECURITY: Remove the hardcoded password and use the secret variable instead
dbAdminPassword: $(dbAdminPassword)
```

All other variable values (ACR login servers, DB URLs) are automatically composed from `uniqueSuffix` and require no further changes.

---

## Step 4 — Set Up the Application Repository

Ensure your application source code repository is on the **`master-aks`** branch and includes:

**`Dockerfile`** — at the repository root, used by the build pipeline.

**`k8s/manifest.yaml`** — a Kubernetes manifest with the following placeholder tokens that the pipeline will substitute at deploy time:

```yaml
image: #{IMAGE_URL}#          # replaced with full ACR image path
env:
  - name: SPRING_DATASOURCE_URL
    value: #{DB_URL}#          # replaced with PostgreSQL JDBC URL
  - name: SPRING_DATASOURCE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-secret        # created automatically by the pipeline
        key: password
```

**`pom.xml`** — Maven build file used by the Maven build task to compile, test, and package the application.

---

## Step 5 — Run the Pipeline

### 5.1 Create the Pipeline

In Azure DevOps, go to **Pipelines → New Pipeline**, connect to your application repository, select the **`master-aks`** branch, and select **Existing Azure Pipelines YAML file**, pointing to `azure-pipeline.yaml`.

### 5.2 Pipeline Stages

When triggered by a push to `main`, the pipeline runs through these stages:

| Stage | Description |
|---|---|
| **Build** | Runs Maven build & tests, then pushes the Docker image to the Dev ACR with the `$(Build.BuildId)` tag |
| **Deploy to Dev** | Applies the Kubernetes manifest to the `dev` namespace on AKS using the Dev ACR image |
| **Manual Approval (Testing)** | Pauses for up to 24 hours awaiting human approval |
| **Deploy to Testing** | Promotes the image from Dev ACR → Test ACR and deploys to the `testing` namespace |
| **Manual Approval (Prod)** | Pauses for up to 24 hours awaiting human approval |
| **Deploy to Prod** | Promotes the image from Test ACR → Prod ACR and deploys to the `prod` namespace |

### 5.3 Approving Promotions

When a `ManualValidation` task fires, an approver will receive a notification in Azure DevOps. Navigate to the pipeline run and click **Review → Approve** to continue, or **Reject** to stop the pipeline.

---

## Verifying the Deployment

After a successful deploy, retrieve the AKS credentials and inspect the running pods:

```bash
# Get credentials for the AKS cluster
az aks get-credentials \
  --resource-group rg-petclinic-aks \
  --name aks-petclinic

# Check pods in each namespace
kubectl get pods -n dev
kubectl get pods -n testing
kubectl get pods -n prod

# Get the service external IP
kubectl get svc -n dev
```

---

## Security Notes

- The `dbAdminPassword` in `aks-infra.sh` and the YAML files is a **placeholder**. Always replace it with a strong, unique password before deploying to any environment.
- Store secrets as **secret pipeline variables** in Azure DevOps, not in YAML files committed to source control.
- The PostgreSQL firewall rule `AllowAzureServices` (IP `0.0.0.0/0.0.0.0`) permits connections from Azure services only. For production hardening, consider using VNet integration and private DNS zones instead.
- The `db-secret` Kubernetes secret is created by the pipeline on every deployment run using `KubernetesManifest@1 createSecret`.

---

## File Reference

| File | Purpose |
|---|---|
| `aks-infra.json` | ARM template — provisions all Azure infrastructure at subscription scope |
| `aks-infra.sh` | Shell script to generate SSH keys and trigger the ARM deployment |
| `azure-pipeline.yaml` | Main pipeline — defines all stages, variables, and stage dependencies |
| `build.yaml` | Reusable pipeline template — Maven build & test, Docker build & push |
| `deploy.yaml` | Reusable pipeline template — optional image promotion, secret creation, and AKS deploy |
| `promote-acr.yaml` | Reusable pipeline template — pulls an image from one ACR, retags it, and pushes to another |
