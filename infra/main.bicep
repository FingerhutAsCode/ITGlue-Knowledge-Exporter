targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Short prefix used to name resources. Lowercase letters and hyphens.')
param namePrefix string = 'itglue-exporter'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Environment label used in tags (e.g. dev, prod).')
param envTag string = 'dev'

@description('Cron expression for the daily export run, in UTC. Default 06:00 UTC.')
param cronExpression string = '0 6 * * *'

@description('vCPU cores for the job replica (string to allow fractional). Pairs 1 vCPU : 2Gi.')
param cpuCores string = '2.0'

@description('Memory for the job replica.')
param memory string = '4Gi'

@description('Max seconds a single execution may run before being stopped.')
param replicaTimeoutSeconds int = 3600

@description('Number of retries for a failed execution.')
param replicaRetryLimit int = 1

@description('Container image the job runs. The pipeline overrides this with the freshly built tag.')
param containerImage string = 'mcr.microsoft.com/k8se/quickstart-jobs:latest'

@description('Base URL for the IT Glue API (use your regional endpoint, e.g. https://api.eu.itglue.com).')
param itglueApiBaseUrl string = 'https://api.itglue.com'

@description('Optional IT Glue API key. Leave as REPLACE_ME to manage the secret manually after deploy.')
@secure()
param itglueApiKey string = 'REPLACE_ME'

@description('Blob container that receives generated artifacts.')
param blobContainerName string = 'artifacts'

@description('Table Storage table used as the document mapping store.')
param mappingTableName string = 'DocumentMapping'

// ---------------------------------------------------------------------------
// Naming
// ---------------------------------------------------------------------------

var rawName = toLower(replace(namePrefix, '-', ''))
var uniq = uniqueString(resourceGroup().id)

var storageAccountName = take('${take(rawName, 9)}st${uniq}', 24)
var registryName = take('${rawName}acr${uniq}', 50)
var keyVaultName = take('${take(rawName, 6)}kv${uniq}', 24)
var logAnalyticsName = '${namePrefix}-logs'
var caeName = '${namePrefix}-cae'
var jobName = '${namePrefix}-export-job'
var identityName = '${namePrefix}-id'

var tags = {
  workload: 'itglue-knowledge-exporter'
  service: 'export-generation'
  environment: envTag
}

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

// Shared user-assigned identity: ACR pull + storage data plane + Key Vault read.
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: logAnalyticsName
    location: location
    tags: tags
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  params: {
    registryName: registryName
    location: location
    tags: tags
    principalId: identity.properties.principalId
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    storageAccountName: storageAccountName
    location: location
    tags: tags
    blobContainerName: blobContainerName
    mappingTableName: mappingTableName
    principalId: identity.properties.principalId
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    keyVaultName: keyVaultName
    location: location
    tags: tags
    principalId: identity.properties.principalId
    itglueApiKey: itglueApiKey
  }
}

module job 'modules/container-app-job.bicep' = {
  name: 'container-app-job'
  params: {
    caeName: caeName
    jobName: jobName
    location: location
    tags: tags
    logAnalyticsName: monitoring.outputs.name
    identityResourceId: identity.id
    identityClientId: identity.properties.clientId
    registryLoginServer: registry.outputs.loginServer
    keyVaultSecretUri: keyvault.outputs.secretUri
    storageAccountName: storage.outputs.storageAccountName
    blobContainerName: blobContainerName
    mappingTableName: mappingTableName
    itglueApiBaseUrl: itglueApiBaseUrl
    containerImage: containerImage
    cpuCores: cpuCores
    memory: memory
    cronExpression: cronExpression
    replicaTimeoutSeconds: replicaTimeoutSeconds
    replicaRetryLimit: replicaRetryLimit
  }
}

// ---------------------------------------------------------------------------
// Outputs (consumed by the GitHub Actions workflow)
// ---------------------------------------------------------------------------

output acrName string = registry.outputs.registryName
output acrLoginServer string = registry.outputs.loginServer
output jobName string = job.outputs.jobName
output storageAccountName string = storage.outputs.storageAccountName
output keyVaultName string = keyvault.outputs.vaultName
