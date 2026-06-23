using './main.bicep'

param namePrefix = 'itgxpt-prod'
param envTag = 'prod'
param location = 'eastus'
param cronExpression = '0 6 * * *'
param cpuCores = '2.0'
param memory = '4Gi'
param replicaTimeoutSeconds = 5400
param itglueApiBaseUrl = 'https://api.itglue.com'
param blobContainerName = 'artifacts'
param mappingTableName = 'DocumentMapping'

// itglueApiKey defaults to REPLACE_ME; manage the prod key in Key Vault.
