LOC="westus3" 

az group create --name rg-dev --location $LOC

az deployment group create \
  --name DeployDev \
  --resource-group rg-dev \
  --template-file petclinic-infra.json \
  --parameters environmentName=dev

az group create --name rg-testing --location $LOC

az deployment group create \
  --name DeployDev \
  --resource-group rg-testing \
  --template-file petclinic-infra.json \
  --parameters environmentName=test

az group create --name rg-prod --location $LOC

az deployment group create \
  --name DeployDev \
  --resource-group rg-prod \
  --template-file petclinic-infra.json \
  --parameters environmentName=prod