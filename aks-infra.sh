ssh-keygen -t rsa -b 4096 -f ~/.ssh/aks_rsa -N ""

az deployment sub create \
  --name petclinic-aks-deploy4 \
  --location westus3 \
  --template-file aks-infra.json \
  --parameters sshRSAPublicKey="$(cat ~/.ssh/aks_rsa.pub)" \
  --parameters dbAdminPassword="Replace-Me-StrongPassword-123!" \
  --parameters region="westus3"
