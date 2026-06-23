@description('Globally unique Key Vault name (3-24 alphanumeric/hyphen).')
param keyVaultName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Principal ID of the managed identity granted secret read access.')
param principalId string

@description('IT Glue API key. Left as REPLACE_ME, no secret is written (manage it manually).')
@secure()
param itglueApiKey string

var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var secretName = 'itglue-api-key'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

// Only (re)write the secret when a real value is supplied. With the default
// placeholder, redeploys never clobber a key you set manually after first deploy.
resource apiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (itglueApiKey != 'REPLACE_ME') {
  parent: keyVault
  name: secretName
  properties: {
    value: itglueApiKey
  }
}

resource secretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, principalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output vaultName string = keyVault.name
output secretUri string = '${keyVault.properties.vaultUri}secrets/${secretName}'
