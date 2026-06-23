@description('Container Apps managed environment name.')
param caeName string

@description('Container Apps job name.')
param jobName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Name of the Log Analytics workspace the environment logs to.')
param logAnalyticsName string

@description('Resource ID of the user-assigned managed identity.')
param identityResourceId string

@description('Client ID of the user-assigned managed identity (passed to the container).')
param identityClientId string

@description('Login server of the container registry (e.g. myacr.azurecr.io).')
param registryLoginServer string

@description('Full Key Vault secret URI for the IT Glue API key.')
param keyVaultSecretUri string

@description('Storage account name (passed to the container).')
param storageAccountName string

@description('Blob container name (passed to the container).')
param blobContainerName string

@description('Mapping table name (passed to the container).')
param mappingTableName string

@description('IT Glue API base URL (passed to the container).')
param itglueApiBaseUrl string

@description('Container image the job runs.')
param containerImage string

@description('vCPU cores (string so fractional values like 0.5 work). 1 vCPU : 2Gi memory.')
param cpuCores string

@description('Memory, e.g. 4Gi.')
param memory string

@description('Cron schedule (UTC).')
param cronExpression string

@description('Max seconds an execution may run.')
param replicaTimeoutSeconds int

@description('Retry count for a failed execution.')
param replicaRetryLimit int

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsName
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: caeName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource exportJob 'Microsoft.App/jobs@2024-03-01' = {
  name: jobName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    environmentId: managedEnvironment.id
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: replicaTimeoutSeconds
      replicaRetryLimit: replicaRetryLimit
      scheduleTriggerConfig: {
        cronExpression: cronExpression
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: registryLoginServer
          identity: identityResourceId
        }
      ]
      secrets: [
        {
          name: 'itglue-api-key'
          keyVaultUrl: keyVaultSecretUri
          identity: identityResourceId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'exporter'
          image: containerImage
          resources: {
            cpu: json(cpuCores)
            memory: memory
          }
          env: [
            {
              name: 'AZURE_CLIENT_ID'
              value: identityClientId
            }
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storageAccountName
            }
            {
              name: 'BLOB_CONTAINER'
              value: blobContainerName
            }
            {
              name: 'MAPPING_TABLE'
              value: mappingTableName
            }
            {
              name: 'ITGLUE_API_BASE_URL'
              value: itglueApiBaseUrl
            }
            {
              name: 'ITGLUE_API_KEY'
              secretRef: 'itglue-api-key'
            }
          ]
        }
      ]
    }
  }
}

output jobName string = exportJob.name
output environmentName string = managedEnvironment.name
