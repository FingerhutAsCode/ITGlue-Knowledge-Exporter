@description('Name of the Log Analytics workspace.')
param logAnalyticsName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

output name string = logAnalytics.name
output customerId string = logAnalytics.properties.customerId
