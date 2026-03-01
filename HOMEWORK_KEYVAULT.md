# Homework — Store the Database Password in Azure Key Vault and Mount it in Kubernetes

Right now the database password travels through the pipeline as a plain variable and gets written into a Kubernetes generic Secret by the pipeline on every deploy. That works, but it means:
- The password must be known to the pipeline and typed into Azure DevOps variables by a human.
- If you rotate the password you must update the pipeline variable manually.
- Any pipeline run can read and log the password.

The better pattern: store the password once in **Azure Key Vault**, give the AKS cluster permission to read it directly, and let Kubernetes mount it as a secret automatically — no pipeline variable needed at all.

---

## What You Will Build

```
Azure Key Vault  ──(CSI driver)──►  Kubernetes Secret  ──►  Pod (env var)
      ▲
      │ (RBAC: Key Vault Secrets User)
      │
AKS Managed Identity
```

---

## Prerequisites

You need the following already in place (they exist from the infrastructure setup):
- AKS cluster `aks-petclinic`
- A Key Vault — you will create one in Task 1
- The AKS kubelet managed identity (already exists, created by the ARM template)

---

## Task 1 — Create the Key Vault and Store the Password

### 1.1 Create the Key Vault

In the Azure Portal, search for **Key Vaults** and click **+ Create**.

| Field | Value |
|---|---|
| **Resource Group** | `rg-petclinic-aks` (put it with the cluster) |
| **Key Vault Name** | `kv-petclinic-<suffix>` (e.g. `kv-petclinic-oyyzir`) |
| **Region** | Same region as your AKS cluster (`West US 3`) |
| **Pricing Tier** | Standard |

On the **Access configuration** tab:
- Permission model: **Azure role-based access control (RBAC)** ← important, do not use Vault access policies

Click **Review + create → Create**.

### 1.2 Store the Password as a Secret

Once the Key Vault is created:

1. Open the Key Vault → **Secrets → + Generate/Import**
2. Fill in:
   - **Name**: `db-password`
   - **Value**: your actual database password (the same one used during ARM deployment)
3. Click **Create**

---

## Task 2 — Grant AKS Permission to Read the Secret

AKS needs an identity that Key Vault will trust. You will use the cluster's existing **kubelet managed identity** — no new identity needed.

### 2.1 Find the Kubelet Identity

```bash
az aks show \
  --resource-group rg-petclinic-aks \
  --name aks-petclinic \
  --query "identityProfile.kubeletidentity.objectId" \
  --output tsv
```

Copy the returned object ID — you will use it in the next step.

### 2.2 Assign the Key Vault Secrets User Role

In the Azure Portal:

1. Open your Key Vault → **Access Control (IAM) → + Add → Add role assignment**
2. Role: **Key Vault Secrets User**
3. Members tab → **Managed identity** → select your subscription → find the identity whose Object ID matches the one from Step 2.1 (it will be named something like `aks-petclinic-agentpool`)
4. Click **Review + assign**

> **Why this role?** "Key Vault Secrets User" allows reading secret values but not creating, updating, or deleting them. It is the minimum permission the cluster needs.

Alternatively via CLI (replace `<objectId>` and `<kvResourceId>`):

```bash
# Get the Key Vault resource ID
KV_ID=$(az keyvault show --name kv-petclinic-oyyzir --query id --output tsv)

# Assign the role to the kubelet identity
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee-object-id <objectId> \
  --assignee-principal-type ServicePrincipal \
  --scope $KV_ID
```

---

## Task 3 — Enable the Secrets Store CSI Driver on AKS

The **Secrets Store CSI Driver** is an add-on that teaches Kubernetes how to talk to Key Vault and automatically sync secrets into the cluster.

```bash
az aks enable-addons \
  --resource-group rg-petclinic-aks \
  --name aks-petclinic \
  --addons azure-keyvault-secrets-provider
```

This takes about 2 minutes. Verify it is running:

```bash
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
```

You should see pods in `Running` state.

---

## Task 4 — Create a SecretProviderClass in Kubernetes

A `SecretProviderClass` is a Kubernetes object that tells the CSI driver exactly which Key Vault, which secret, and which managed identity to use. Create one per namespace.

Create a file called `secret-provider.yaml` with the content below. Replace the three placeholder values with your own.

```yaml
# secret-provider.yaml
#
# This object is the "bridge" between Kubernetes and Key Vault.
# It tells the CSI driver: "when a pod asks for a secret, go to THIS
# Key Vault, authenticate as THIS identity, and fetch THIS secret."
# Without it, Kubernetes has no idea that Key Vault even exists.

apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: petclinic-db-secret-provider
  namespace: dev                      # Repeat for testing and prod namespaces
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    clientID: ""                      # Leave empty — kubelet managed identity is used automatically
    keyvaultName: "kv-petclinic-oyyzir"    # ← REPLACE with your Key Vault name
    objects: |
      array:
        - |
          objectName: db-password     # Must match the secret name you created in Task 1.2
          objectType: secret
    tenantId: "<YOUR-TENANT-ID>"      # ← REPLACE: az account show --query tenantId --output tsv

  # secretObjects tells the CSI driver to also create a native Kubernetes
  # Secret from the Key Vault value. This is what the pod reads at runtime —
  # the pod never talks to Key Vault directly.
  secretObjects:
  - secretName: db-secret             # This is the same name the manifest already references
    type: Opaque
    data:
    - objectName: db-password
      key: password                   # The pod reads this key via secretKeyRef
```

Apply it to each namespace:

```bash
kubectl apply -f secret-provider.yaml -n dev

# Duplicate the file, change namespace to testing, apply again
kubectl apply -f secret-provider.yaml -n testing

# Duplicate the file, change namespace to prod, apply again
kubectl apply -f secret-provider.yaml -n prod
```

---

## Task 5 — Update the Kubernetes Manifest to Mount the CSI Volume

The pod needs to mount the CSI volume to trigger the secret sync. Add a `volume` and a `volumeMount` to `k8s/manifest.yaml`. The `env` section using `secretKeyRef` stays exactly as it is — you are only adding the mount that activates Key Vault sync.

```yaml
# In your Deployment spec, add under the container:
spec:
  containers:
  - name: petclinic
    # ... existing env section stays unchanged ...
    env:
    - name: SPRING_DATASOURCE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret     # ← This already exists. No change needed here.
          key: password

    # Add this volumeMount — it tells the container to mount the CSI volume.
    # The pod does not actually read files from this path; the mount is what
    # triggers the CSI driver to pull the secret from Key Vault and create
    # the Kubernetes Secret object above.
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets-store"
      readOnly: true

  # Add this volume — it links to the SecretProviderClass you created in Task 4.
  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "petclinic-db-secret-provider"
```

---

## Task 6 — Remove the createSecret Step from the Pipeline

Now that Key Vault manages the secret, the pipeline no longer needs to create it. In `deploy.yaml`, delete the `KubernetesManifest@1 createSecret` task entirely:

```yaml
# DELETE this entire block from deploy.yaml:
- task: KubernetesManifest@1
  displayName: 'Create Database Secret'
  inputs:
    action: 'createSecret'
    ...
```

Also remove the `dbPassword` parameter from `deploy.yaml`, `azure-pipeline.yaml`, and the `dbAdminPassword` variable — the pipeline no longer needs to know the password at all.

---

## How to Verify It All Works

```bash
# 1. Check the SecretProviderClass was created
kubectl get secretproviderclass -n dev

# 2. After a deploy, check the Kubernetes Secret was created by the CSI driver
kubectl get secret db-secret -n dev

# 3. Confirm the pod is running (not crashing due to missing secret)
kubectl get pods -n dev

# 4. Confirm the app can reach the database — open the app in a browser
kubectl get svc -n dev
# Navigate to the EXTERNAL-IP shown
```

---

## Checklist

- [ ] Key Vault created in `rg-petclinic-aks` with RBAC permission model
- [ ] Secret `db-password` created in Key Vault
- [ ] Kubelet managed identity granted **Key Vault Secrets User** role on the Key Vault
- [ ] Secrets Store CSI driver add-on enabled on AKS
- [ ] `SecretProviderClass` applied to all three namespaces (dev, testing, prod)
- [ ] `k8s/manifest.yaml` updated with `volumes` and `volumeMounts`
- [ ] `createSecret` task removed from `deploy.yaml`
- [ ] `dbAdminPassword` variable removed from pipeline
- [ ] Pipeline triggered, pods running, app reachable in browser
