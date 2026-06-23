# IT Glue Knowledge Exporter — Export & Generation Service

This repo is **service 1** of the pipeline: a scheduled job that pulls the IT Glue
export, processes it into HTML + PDF artifacts, and writes them to blob storage
along with per-document state in a mapping table. Distribution to SharePoint,
Salesforce, and other Document Repositories are done via **service 2** and lives separately — the two share only
the storage account and mapping table as their interconnect.

The export runs as an **Azure Container Apps Job** (consumption plan) on a daily
schedule. At 2 vCPU / 4 GiB once a day, the compute sits inside the monthly free
grant, so the only standing cost is the Basic container registry (~$5/month).

## What gets deployed

- User-assigned managed identity (used for everything — no secrets in code)
- Storage account with a blob container (`artifacts`) and a table (`DocumentMapping`); shared-key access disabled, identity-only data plane
- Azure Container Registry (Basic)
- Key Vault (RBAC) holding the IT Glue API key
- Log Analytics workspace
- Container Apps environment + the scheduled export job
- Role assignments granting the identity: Storage Blob Data Contributor, Storage Table Data Contributor, AcrPull, Key Vault Secrets User

```
infra/
  main.bicep                 orchestrates everything
  modules/                   storage, registry, keyvault, monitoring, container-app-job
  dev.bicepparam             dev parameters
  prod.bicepparam            prod parameters
src/
  Dockerfile                 PowerShell 7 on Linux (add your deps here)
  scripts/entrypoint.ps1     <-- DROP YOUR LOGIC HERE
.github/workflows/deploy.yml OIDC build + deploy
```

## Where your code goes

Open `src/scripts/entrypoint.ps1`. Config loading and managed-identity auth are
already wired; fill in the three TODO sections (pull export, process documents,
write to blob + table) or call your own scripts from there. Add system packages
(e.g. a PDF renderer) and PowerShell modules in `src/Dockerfile`.

## One-time setup

### 1. Create the GitHub OIDC identity in Azure

Register an app (or use a service principal) and add a federated credential for
this repo, then grant it rights on the subscription or a resource group.

```bash
az ad app create --display-name "gh-itglue-exporter"
# capture the appId, then create a service principal for it:
az ad sp create --id <appId>

# Federated credential for pushes to main:
az ad app federated-credential create --id <appId> --parameters '{
  "name": "gh-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:FingerhutAsCode/ITGlue-Knowledge-Exporter:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

> **Important:** the template creates role assignments, so the deploying identity
> needs `Owner`, or `Contributor` **plus** `User Access Administrator`, on the
> target scope. `Contributor` alone cannot assign roles and the deploy will fail.

```bash
az role assignment create --assignee <appId> --role "Owner" \
  --scope /subscriptions/<subId>/resourceGroups/rg-itglue-exporter
```

(If the resource group doesn't exist yet, scope to the subscription for the first
run, or create the group manually first.)

### 2. Add GitHub repo secrets

In the repo settings → Secrets and variables → Actions:

- `AZURE_CLIENT_ID` — the app's appId
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

### 3. Set the IT Glue API key

The Bicep does not store the key by default (the param stays `REPLACE_ME`, so
redeploys never clobber it). After the first deploy, set it once:

```bash
az keyvault secret set \
  --vault-name <keyVaultName-from-deploy-output> \
  --name itglue-api-key \
  --value "<your IT Glue API key>"
```

(Alternatively, pass `itglueApiKey` from a GitHub secret in the workflow for
fully-automated provisioning.)

## Deploy

Push to `main` (or run the workflow manually). The pipeline:

1. Logs in with OIDC (no client secret)
2. Ensures the resource group
3. Deploys the Bicep (creates the registry on first run; the job starts on the
   public placeholder image)
4. Builds and pushes your image with ACR Tasks (`az acr build` — no Docker needed
   on the runner)
5. Points the job at the freshly built image tag

The job then runs on its daily schedule. To trigger a run on demand for testing:

```bash
az containerapp job start --name <jobName> --resource-group rg-itglue-exporter
```

## Notes

- The free Container Apps grant is **per subscription**, shared across all
  consumption workloads in it — heavy neighbours reduce your free run budget.
- Use your regional IT Glue endpoint in the param file if you're not on the
  default (`https://api.eu.itglue.com`, etc.).
- The IT Glue document body/attachments aren't available through the per-resource
  API — the account export (the ZIP this job downloads) is the supported path.
