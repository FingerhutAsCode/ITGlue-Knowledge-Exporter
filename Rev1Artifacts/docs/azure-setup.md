# Azure Setup

## 1. Service Principal (GitHub Actions deployment)
Via Azure Cloud Shell
```bash
az ad sp create-for-rbac --name "itg-knowledge-exporter" \
  --role contributor \
  --scopes /subscriptions/<sub-id>/resourceGroups/<rg-name> \
  --sdk-auth
```
Save a copy of the output as you will need to paste the JSON output as `AZURE_CREDENTIALS` GitHub secret.

## 2. App Registration (Graph API access)
Azure Portal → Entra ID → App Registrations → New Registration

Required API Permissions (Application):
- `Group.ReadWrite.All`
- `User.Read.All`
- `Directory.ReadWrite.All`

Grant admin consent after adding permissions.

## 3. GitHub Secrets

| Secret | Value |
|--------|-------|
| `AZURE_CREDENTIALS` | Service principal JSON |
| `AZURE_SUBSCRIPTION_ID` | Your subscription ID |
| `AZURE_RESOURCE_GROUP` | e.g. `rg-itg` |
| `AZURE_FUNCTION_APP_NAME` | e.g. `func-itg` |
| `OKTA_WEBHOOK_SECRET` | From Okta Event Hook config |
| `AZURE_CLIENT_SECRET` | App registration client secret |