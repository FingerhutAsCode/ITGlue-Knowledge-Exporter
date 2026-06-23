// modules/api-connections.bicep
// Provisions the API Connection resources (Microsoft.Web/connections) used by
// the Logic Apps to talk to Salesforce and SharePoint Online.
//
// IMPORTANT: Bicep/ARM can only create the connection *shell*. The OAuth
// consent/token grant for both Salesforce and SharePoint must be completed
// manually, once, via the Azure Portal:
//   Resource Group -> <connection-name> -> "Edit API connection" -> Authorize
// This is a hard limitation of interactive OAuth connectors - it cannot be
// scripted through ARM/Bicep. See README.md for the step-by-step.

param location string
param env string
// param storageAccountName string
// param sharePointSiteUrl string

@description('When true, authenticates against Salesforce sandbox (test.salesforce.com) instead of production (login.salesforce.com).')
param salesforceSandbox bool = false

// ---------------------------------------------------------------------------
// Salesforce connection
// ---------------------------------------------------------------------------
resource salesforceConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'salesforce-connection-${env}'
  location: location
  properties: {
    displayName: 'ITGlueSync-Salesforce-${env}'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'salesforce')
    }
    parameterValues: {
      'token:LoginUri': salesforceSandbox ? 'https://test.salesforce.com' : 'https://login.salesforce.com'
    }
  }
}

// ---------------------------------------------------------------------------
// SharePoint Online connection
// ---------------------------------------------------------------------------
resource sharePointConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'sharepoint-connection-${env}'
  location: location
  properties: {
    displayName: 'ITGlueSync-SharePoint-${env}'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'sharepointonline')
    }
    // parameterValues intentionally omitted - OAuth consent completed manually post-deploy
  }
}

// ---------------------------------------------------------------------------
// Outputs consumed by main.bicep when wiring up the Logic Apps' $connections
// ---------------------------------------------------------------------------
output salesforceConnectionId string = salesforceConnection.id
output salesforceConnectionName string = salesforceConnection.name
output salesforceManagedApiId string = subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'salesforce')

output sharePointConnectionId string = sharePointConnection.id
output sharePointConnectionName string = sharePointConnection.name
output sharePointManagedApiId string = subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'sharepointonline')
