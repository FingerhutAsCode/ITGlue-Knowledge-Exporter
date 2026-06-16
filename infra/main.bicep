// main.bicep
// Entry point for the ITGlue -> SharePoint/Salesforce sync solution.
// Deploys: Table Storage (document mapping), API connections, and 3 Consumption Logic Apps
// (orchestrator, write-to-salesforce, write-to-sharepoint).
//
// Deploy at resource-group scope:
//   az deployment group create -g rg-itgke-<env> -f infra/main.bicep -p infra/params/<env>.bicepparam

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment short name, used in resource naming (e.g. dev, test, prod)')
@minLength(2)
@maxLength(10)
param env string

@description('Base name used to derive resource names. Keep short - storage account names have a 24 char limit.')
@minLength(3)
@maxLength(11)
param baseName string = 'itgke'

@description('SharePoint site URL the write-to-sharepoint flow will target. Set after you confirm the target site.')
param sharePointSiteUrl string = 'https://CHANGE_ME.sharepoint.com/sites/CHANGE_ME'

@description('Salesforce REST API version used for Knowledge publish/edit actions')
param salesforceApiVersion string = 'v58.0'

var storageAccountName = toLower('st${env}${baseName}')
var tableName = 'DocumentMapping'

// ---------------------------------------------------------------------------
// Storage account + mapping table
// ---------------------------------------------------------------------------
module storage 'modules/storage-table.bicep' = {
  name: 'storage-${env}'
  params: {
    location: location
    storageAccountName: storageAccountName
    tableName: tableName
  }
}

// ---------------------------------------------------------------------------
// API connections (Salesforce, SharePoint, Azure Tables)
// ---------------------------------------------------------------------------
module connections 'modules/api-connections.bicep' = {
  name: 'connections-${env}'
  params: {
    location: location
    env: env
    storageAccountName: storageAccountName
    sharePointSiteUrl: sharePointSiteUrl
  }
}

// ---------------------------------------------------------------------------
// Logic App: write-to-salesforce (child workflow)
// ---------------------------------------------------------------------------
module salesforceFlow 'modules/logicapp-consumption.bicep' = {
  name: 'la-salesforce-${env}'
  params: {
    name: 'la-write-to-salesforce-${env}'
    location: location
    definitionFilePath: 'workflows/write-to-salesforce.json'
    workflowParameters: {
      storageAccountName: { value: storageAccountName }
      salesforceApiVersion: { value: salesforceApiVersion }
    }
    connectionsParam: {
      '$connections': {
        value: {
          salesforce: {
            connectionId: connections.outputs.salesforceConnectionId
            connectionName: connections.outputs.salesforceConnectionName
            id: connections.outputs.salesforceManagedApiId
          }
        }
      }
    }
  }
  dependsOn: [
    storage
  ]
}

// ---------------------------------------------------------------------------
// Logic App: write-to-sharepoint (child workflow)
// ---------------------------------------------------------------------------
module sharepointFlow 'modules/logicapp-consumption.bicep' = {
  name: 'la-sharepoint-${env}'
  params: {
    name: 'la-write-to-sharepoint-${env}'
    location: location
    definitionFilePath: 'workflows/write-to-sharepoint.json'
    workflowParameters: {
      storageAccountName: { value: storageAccountName }
      sharePointSiteUrl: { value: sharePointSiteUrl }
    }
    connectionsParam: {
      '$connections': {
        value: {
          sharepointonline: {
            connectionId: connections.outputs.sharePointConnectionId
            connectionName: connections.outputs.sharePointConnectionName
            id: connections.outputs.sharePointManagedApiId
          }
        }
      }
    }
  }
  dependsOn: [
    storage
  ]
}

// ---------------------------------------------------------------------------
// Logic App: orchestrator (parent workflow - calls both children sequentially)
// ---------------------------------------------------------------------------
module orchestrator 'modules/logicapp-consumption.bicep' = {
  name: 'la-orchestrator-${env}'
  params: {
    name: 'la-orchestrator-${env}'
    location: location
    definitionFilePath: 'workflows/orchestrator.json'
    workflowParameters: {
      storageAccountName: { value: storageAccountName }
      salesforceFlowUrl: { value: salesforceFlow.outputs.triggerUrl }
      sharepointFlowUrl: { value: sharepointFlow.outputs.triggerUrl }
    }
    connectionsParam: {}
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output storageAccountName string = storageAccountName
output orchestratorTriggerUrl string = orchestrator.outputs.triggerUrl
output salesforceFlowName string = salesforceFlow.outputs.logicAppName
output sharepointFlowName string = sharepointFlow.outputs.logicAppName
output postDeploySteps string = 'Open the salesforce-connection and sharepoint-connection resources in the portal under "Edit API connection" to complete OAuth consent. See README.md.'
