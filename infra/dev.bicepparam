using './main.bicep'

param namePrefix = 'itgxpt-dev'
param envTag = 'dev'
param location = 'eastus'
param cronExpression = '0 6 * * *'
param cpuCores = '2.0'
param memory = '4Gi'
param replicaTimeoutSeconds = 3600
param itglueApiBaseUrl = 'https://api.itglue.com'
param blobContainerName = 'artifacts'
param mappingTableName = 'DocumentMapping'

// itglueApiKey is intentionally not set here -> defaults to REPLACE_ME.
// Set the real key once after first deploy (see README), or pass it from a
// GitHub secret in the workflow if you prefer fully-automated provisioning.
