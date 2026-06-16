// modules/storage-table.bicep
// Storage account hosting the DocumentMapping table used to track
// source (IT Glue) -> destination (Salesforce, SharePoint, ...) document IDs.

param location string
param storageAccountName string
param tableName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource mappingTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: tableService
  name: tableName
}

// Schema reference (Table Storage is schemaless - this is documentation only):
//   PartitionKey   : ITGlue document ID
//   RowKey         : target system name, e.g. "Salesforce", "SharePoint"
//   DestinationId  : record/item ID in the target system
//                    (Salesforce: KnowledgeArticleId; SharePoint: list item ID)
//   SourceVersion  : IT Glue document version / updated-at timestamp
//   LastSyncedUtc  : ISO 8601 timestamp of last successful sync
//   Status         : Success | Failed | Pending

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output tableName string = mappingTable.name
