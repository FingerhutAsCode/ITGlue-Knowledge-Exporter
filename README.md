# ITGlue Sync

Automation that takes a cleaned IT Glue document export and writes it to
multiple destination systems (Salesforce Knowledge, SharePoint), tracking
source -> destination document IDs in an Azure Table so future updates know
whether to create or update a record.

## Architecture

```
IT Glue export + cleanup (external/existing - not in this repo)
  -> Orchestrator Logic App (Consumption)
        -> Get/Set mapping in Azure Table "DocumentMapping"
        -> Call_SharePoint  -> write-to-sharepoint Logic App (Consumption)
        -> Call_Salesforce  -> write-to-salesforce Logic App (Consumption)
```

All three Logic Apps run on the **Consumption** plan (pay-per-execution, no
reserved compute) since expected volume is low. See "Cost model" below.

## Repo layout

```
itglue-sync/
├── .github/workflows/deploy.yml      GitHub Actions: Bicep deploy via OIDC
├── infra/
│   ├── main.bicep                    Entry point, wires all modules together
│   ├── modules/
│   │   ├── storage-table.bicep       Storage account + DocumentMapping table
│   │   ├── api-connections.bicep     Salesforce + SharePoint API Connections
│   │   └── logicapp-consumption.bicep  Generic Consumption Logic App module
│   ├── workflows/
│   │   ├── orchestrator.json         Parent workflow definition
│   │   ├── write-to-salesforce.json  Salesforce Knowledge child workflow
│   │   └── write-to-sharepoint.json  SharePoint child workflow (PLACEHOLDER)
│   └── params/
│       ├── dev.bicepparam
│       └── prod.bicepparam
└── README.md
```

## Prerequisites

- Azure subscription + resource group created ahead of time (this repo does
  not create the resource group itself; `az group create` first).
- GitHub repo configured with an Azure AD app registration + federated
  credential for OIDC login (no client secret stored in GitHub). See
  "GitHub OIDC setup" below.
- Salesforce: a Connected App configured for OAuth (interactive), Knowledge
  enabled, article type `Knowledge__kav` with rich text field
  `Article_Body__c` (confirmed correct for this org).
- SharePoint: target site/library decided (not yet finalized - see
  "Known gaps").

## GitHub secrets required

Set these in the repo (Settings -> Secrets and variables -> Actions):

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | App registration (federated credential) client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `AZURE_RESOURCE_GROUP` | Resource group the resources deploy into |

### GitHub OIDC setup (one-time, in Azure)

```bash
# Create app registration
az ad app create --display-name "github-itgluesync-deploy"

# Note the appId from the output, then create a service principal
az ad sp create --id <appId>

# Grant Contributor on the target resource group
az role assignment create \
  --assignee <appId> \
  --role Contributor \
  --scope /subscriptions/<subId>/resourceGroups/<rgName>

# Add federated credential trusting GitHub Actions on main branch
az ad app federated-credential create \
  --id <appId> \
  --parameters '{
    "name": "github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<org>/<repo>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

## Deployment

Push to `main` (with changes under `infra/`) triggers the workflow, or run it
manually via the Actions tab ("Run workflow" -> choose environment).

```bash
# Local/manual equivalent
az deployment group create \
  -g <resource-group> \
  -f infra/main.bicep \
  -p infra/params/dev.bicepparam
```

## Required manual steps after first deploy

These cannot be automated through ARM/Bicep and must be done once per
environment, in the Azure Portal:

1. **Salesforce API connection OAuth consent**
   Resource Group -> `salesforce-connection-<env>` -> **Edit API connection**
   -> Authorize -> sign in with the Salesforce service/integration account.

2. **SharePoint API connection OAuth consent**
   Resource Group -> `sharepoint-connection-<env>` -> **Edit API connection**
   -> Authorize -> sign in with the SharePoint service account.

3. **Grant the orchestrator's managed identity access to Table Storage**
   The orchestrator and both child workflows call Azure Table Storage
   directly via `authentication: ManagedServiceIdentity` (not the managed
   Table Storage connector) to avoid provisioning a 3rd API connection.
   Each Logic App needs a **system-assigned managed identity** enabled, and
   that identity needs the **Storage Table Data Contributor** role on the
   storage account:

   ```bash
   # Enable system-assigned identity (if not already on by default - confirm
   # in portal under each Logic App -> Identity)
   az resource update \
     --ids <logicAppResourceId> \
     --set identity.type=SystemAssigned

   # Get the principal ID, then grant the role
   az role assignment create \
     --assignee <principalId> \
     --role "Storage Table Data Contributor" \
     --scope <storageAccountResourceId>
   ```

   Do this for the orchestrator, write-to-salesforce, and write-to-sharepoint
   Logic Apps (each makes its own Table Storage calls).

## Known gaps / things to confirm before production use

- **write-to-sharepoint.json is a structural placeholder.** It mirrors the
  get-mapping -> branch -> create/update -> respond shape so the orchestrator
  integration works end-to-end, but the actual SharePoint actions
  (`Update_File` / `Create_File`) have `CHANGE_ME` paths and need the real
  target site, library, and field mapping filled in.

- **Image `<img src>` rewriting happens in `Rewrite_HTML` as a no-op
  placeholder.** The recommended approach is to do the HTML string
  replacement in the upstream IT Glue cleanup step (which already has the
  parsed image list) rather than inside Logic Apps expressions, which get
  unreadable fast for N image replacements. If you want it done inside the
  Salesforce child flow instead, this needs to be built out before go-live.

- **Salesforce image URL pattern is unconfirmed.**
  `/sfc/servlet.shepherd/version/download/{ContentVersionId}` is the
  best-documented guess for an inline-renderable image URL inside a
  Knowledge Article body, but the exact accessible URL format can vary by
  org sharing configuration. Before relying on this in production: manually
  upload one image into a real Knowledge Article via the Salesforce UI rich
  text editor and confirm the resulting `<img src="...">` pattern matches.

- **Knowledge rich text field length limit (~131,072 characters).** Worth a
  sanity check against your largest IT Glue articles once images are
  swapped to short URLs instead of inline base64.

- **`sharePointSiteUrl` and Salesforce API version are placeholder values**
  in both `.bicepparam` files - update before deploying to a real
  environment.

## Cost model (Consumption plan)

No reserved infrastructure cost. You pay per execution:

- First 4,000 built-in actions/month free; $0.000025/action after that.
- Standard connector calls (SharePoint): $0.000125/call.
- Premium connector calls (Salesforce): $0.001/call.
- Run history/data retention: $0.12/GB/month.

At low/occasional sync volume this is expected to be a few dollars a month
at most. Each end-to-end sync produces 3 separate Logic App run histories
(orchestrator + 2 children), each billed independently.

## Mapping table schema (`DocumentMapping`)

| Field | Description |
|---|---|
| `PartitionKey` | IT Glue document ID |
| `RowKey` | Target system name (`Salesforce`, `SharePoint`) |
| `DestinationId` | Record ID in the target system (Salesforce: `KnowledgeArticleId`; SharePoint: list item ID) |
| `SourceVersion` | IT Glue document version / updated-at |
| `LastSyncedUtc` | ISO 8601 timestamp of last sync attempt |
| `Status` | `Success` \| `Failed` \| `Pending` |
