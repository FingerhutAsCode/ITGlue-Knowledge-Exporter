// modules/logicapp-consumption.bicep
// Generic, reusable module for deploying a single Consumption-plan Logic App
// with its workflow definition loaded from a JSON file in the repo.

@description('Name of the Logic App resource')
param name string

param location string

@description('Workflow definition object loaded by the caller (for example: loadJsonContent(...) in the calling file).')
param definition object

@description('Values for parameters declared inside the workflow JSON (e.g. storageAccountName, flow URLs). Each value must be wrapped as { value: ... }.')
param workflowParameters object = {}

@description('The $connections parameter value block, wired to API Connection resource IDs. Pass {} if the workflow uses no managed connectors.')
param connectionsParam object = {}

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: name
  location: location
  properties: {
    state: 'Enabled'
    definition: definition
    parameters: union(workflowParameters, connectionsParam)
  }
}

output logicAppId string = logicApp.id
output logicAppName string = logicApp.name
output triggerUrl string = listCallbackUrl('${logicApp.id}/triggers/manual', '2019-05-01').value
