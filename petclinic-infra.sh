az deployment sub create \
  --name petclinic-sub-deploy \
  --location westus3 \
  --template-file petclinic-infra.json \
  --parameters region=westus3
