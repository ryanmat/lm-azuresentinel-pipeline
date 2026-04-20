// Description: Log Analytics Workspace module with Microsoft Sentinel onboarding.
// Description: Creates LAW PerGB2018 30-day retention, then enables Sentinel via onboardingStates.

targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Tags applied to the workspace.')
param tags object

@description('Log Analytics Workspace name.')
param workspaceName string

@description('Retention in days.')
param retentionDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = {
  scope: workspace
  name: 'default'
  properties: {}
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output customerId string = workspace.properties.customerId
