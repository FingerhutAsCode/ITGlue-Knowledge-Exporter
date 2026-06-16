# Azure Setup
az ad sp create-for-rbac --name "itg-knowledge-exporter" \
  --role contributor \
  --scopes /subscriptions/fc7000aa-087f-450f-8de3-ddaf45d23c44/resourceGroups/rg-itgke-dev \
  --sdk-auth