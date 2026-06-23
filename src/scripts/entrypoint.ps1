#requires -Version 7
<#
  entrypoint.ps1 - PLACEHOLDER entrypoint for the IT Glue export/generation job.

  This runs once per day inside the Container Apps Job. The scaffold around the
  TODOs (config loading + managed-identity auth) is wired for you. Drop your
  existing export pull, document processing, and storage writes into the three
  TODO sections below, or call your own scripts from here.

  Environment variables provided by the infrastructure:
    AZURE_CLIENT_ID      - client ID of the user-assigned managed identity
    STORAGE_ACCOUNT_NAME - target storage account
    BLOB_CONTAINER       - container for generated HTML/PDF artifacts
    MAPPING_TABLE        - Table Storage table (DocumentMapping)
    ITGLUE_API_BASE_URL  - IT Glue API base URL
    ITGLUE_API_KEY       - IT Glue API key (injected from Key Vault as a secret)
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Log {
  param([string]$Message)
  Write-Host "[$([DateTime]::UtcNow.ToString('o'))] $Message"
}

# --- Configuration -----------------------------------------------------------
$config = @{
  ClientId       = $env:AZURE_CLIENT_ID
  StorageAccount = $env:STORAGE_ACCOUNT_NAME
  BlobContainer  = $env:BLOB_CONTAINER
  MappingTable   = $env:MAPPING_TABLE
  ItGlueBaseUrl  = $env:ITGLUE_API_BASE_URL
}

foreach ($key in 'StorageAccount', 'BlobContainer', 'MappingTable', 'ItGlueBaseUrl') {
  if ([string]::IsNullOrWhiteSpace($config[$key])) {
    throw "Missing required environment variable backing '$key'."
  }
}

Write-Log 'Starting IT Glue export run.'
Write-Log "Storage: $($config.StorageAccount) | container: $($config.BlobContainer) | table: $($config.MappingTable)"

# --- Managed-identity auth ---------------------------------------------------
# The job's user-assigned identity already holds Storage Blob Data Contributor
# and Storage Table Data Contributor on the account. Authenticate with it -
# no keys, no connection strings.
Write-Log "Authenticating with managed identity ($($config.ClientId))..."
Connect-AzAccount -Identity -AccountId $config.ClientId | Out-Null
$storageContext = New-AzStorageContext -StorageAccountName $config.StorageAccount -UseConnectedAccount

# Pull IT Glue API key from Key Vault when not provided as an environment variable.
if ([string]::IsNullOrWhiteSpace($env:ITGLUE_API_KEY)) {
  $keyVaultName = $env:KEYVAULT_NAME
  if ([string]::IsNullOrWhiteSpace($keyVaultName)) {
    $keyVaultName = $env:KEY_VAULT_NAME
  }

  if (-not [string]::IsNullOrWhiteSpace($keyVaultName)) {
    $secretName = if ([string]::IsNullOrWhiteSpace($env:ITGLUE_API_KEY_SECRET_NAME)) {
      'itglue-api-key'
    }
    else {
      $env:ITGLUE_API_KEY_SECRET_NAME
    }

    Write-Log "Fetching secret '$secretName' from Key Vault '$keyVaultName'..."
    try {
      $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -AsPlainText
      if (-not [string]::IsNullOrWhiteSpace($secret)) {
        $env:ITGLUE_API_KEY = $secret
      }
    }
    catch {
      throw "Failed to read secret '$secretName' from Key Vault '$keyVaultName': $($_.Exception.Message)"
    }
  }
}

if ([string]::IsNullOrWhiteSpace($env:ITGLUE_API_KEY)) {
  throw "IT Glue API key not present. Set ITGLUE_API_KEY or configure KEYVAULT_NAME/KEY_VAULT_NAME with secret 'itglue-api-key'."
}


# =============================================================================
# TODO 1 - PULL THE EXPORT FROM IT GLUE
#   POST to the IT Glue /exports endpoint, poll until the export is ready, then
#   download the ZIP. Send the key as the 'x-api-key' header; base URL is in
#   $config.ItGlueBaseUrl and the key is in $env:ITGLUE_API_KEY.
# =============================================================================

Get-ITGlueExport.ps1 -api_key $env:ITGLUE_API_KEY -destination_path 'C:\Temp' -destination_name 'itglue_export.zip'

# =============================================================================
# TODO 2 - PROCESS DOCUMENTS
#   Unpack the export, clean the content, and render the HTML + PDF artifacts.
# =============================================================================

# =============================================================================
# TODO 3 - WRITE TO BLOB + UPDATE THE MAPPING TABLE
#   Upload artifacts to $config.BlobContainer via $storageContext, then upsert
#   per-document version/state rows into $config.MappingTable.
#   Example blob upload:
#     Set-AzStorageBlobContent -File <localPath> -Container $config.BlobContainer `
#       -Blob <blobName> -Context $storageContext -Force
# =============================================================================

Write-Log 'Placeholder run complete. Replace the TODO sections with your logic.'
