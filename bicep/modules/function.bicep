// Description: Storage, App Insights, and Linux Consumption Function App with System-Assigned MI.
// Description: Grants the MI EH Data Receiver on the hub and Monitoring Metrics Publisher on the DCR.

targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('App Service plan name.')
param planName string

@description('Function App name. Must be globally unique.')
param functionAppName string

@description('Storage account name. Must be globally unique, 3-24 chars lowercase alphanumeric.')
param storageName string

@description('Application Insights resource name.')
param appInsightsName string

@description('Log Analytics workspace resource ID for App Insights workspace-based mode.')
param workspaceId string

@description('Event Hub namespace name (for MI binding).')
param eventHubNamespaceName string

@description('Event Hub name.')
param eventHubName string

@description('Event Hub listen authorization rule name (not used at runtime with MI, kept for output).')
param eventHubAuthRuleName string

@description('Data Collection Endpoint Logs Ingestion URL.')
param dceEndpoint string

@description('Data Collection Rule immutable ID.')
param dcrImmutableId string

@description('Data Collection Rule resource ID (for role scope).')
param dcrId string

@description('Stream name in the DCR.')
param streamName string

var ehDataReceiverRoleId = 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde'
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
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

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceId
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Y1 Dynamic (Consumption) Linux plan. East US had 0 quota on this sub; East US 2 has
// existing Y1 plans for this subscription so quota is expected to be available.
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Python|3.12'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'AzureWebJobsFeatureFlags'
          value: 'EnableWorkerIndexing'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'EventHubConnection__fullyQualifiedNamespace'
          value: '${eventHubNamespaceName}.servicebus.windows.net'
        }
        {
          name: 'EventHubConnection__credential'
          value: 'managedidentity'
        }
        {
          name: 'EVENT_HUB_NAME'
          value: eventHubName
        }
        {
          name: 'DCE_ENDPOINT'
          value: dceEndpoint
        }
        {
          name: 'DCR_IMMUTABLE_ID'
          value: dcrImmutableId
        }
        {
          name: 'DCR_STREAM_NAME'
          value: streamName
        }
      ]
    }
  }
}

resource ehNamespace 'Microsoft.EventHub/namespaces@2024-01-01' existing = {
  name: eventHubNamespaceName
}

resource ehHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' existing = {
  parent: ehNamespace
  name: eventHubName
}

resource ehDataReceiverAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: ehHub
  name: guid(ehHub.id, functionApp.id, ehDataReceiverRoleId)
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ehDataReceiverRoleId)
  }
}

resource dcrExisting 'Microsoft.Insights/dataCollectionRules@2023-03-11' existing = {
  name: last(split(dcrId, '/'))
}

resource metricsPublisherAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: dcrExisting
  name: guid(dcrId, functionApp.id, monitoringMetricsPublisherRoleId)
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
  }
}

output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
output principalId string = functionApp.identity.principalId
output storageAccountName string = storage.name
output appInsightsName string = appInsights.name
output unusedAuthRuleName string = eventHubAuthRuleName
