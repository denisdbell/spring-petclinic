az deployment sub create \
  --name petclinic-sub-deploy \
  --location westus3 \
  --template-file main.json \
  --parameters region=westus3
