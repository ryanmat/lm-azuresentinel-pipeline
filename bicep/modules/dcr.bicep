// Description: Data Collection Endpoint, Data Collection Rule, and custom LogicMonitorAlerts_CL table.
// Description: Defines the Logs Ingestion API path from the Function into the Log Analytics workspace.

targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Data Collection Endpoint name.')
param dceName string

@description('Data Collection Rule name.')
param dcrName string

@description('Log Analytics Workspace resource ID.')
param workspaceId string

@description('Log Analytics Workspace name (used for child table resource).')
param workspaceName string

@description('Custom table name. Must end with _CL.')
param customTableName string

@description('Stream name in the DCR. Must start with Custom-.')
param streamName string

var columns = [
  { name: 'TimeGenerated', type: 'datetime' }
  { name: 'LmAlertId', type: 'string' }
  { name: 'AlertType', type: 'string' }
  { name: 'Severity', type: 'string' }
  { name: 'Status', type: 'string' }
  { name: 'DeviceName', type: 'string' }
  { name: 'DeviceDisplayName', type: 'string' }
  { name: 'DeviceGroups', type: 'string' }
  { name: 'DataSourceOrGroup', type: 'string' }
  { name: 'InstanceName', type: 'string' }
  { name: 'DataPointName', type: 'string' }
  { name: 'DataPointValue', type: 'string' }
  { name: 'ThresholdValue', type: 'string' }
  { name: 'AlertMessage', type: 'string' }
  { name: 'StartedTime', type: 'datetime' }
  { name: 'ClearedTime', type: 'datetime' }
  { name: 'AckUser', type: 'string' }
  { name: 'PortalUrl', type: 'string' }
  { name: 'RawAlert', type: 'dynamic' }
]

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: customTableName
  properties: {
    schema: {
      name: customTableName
      columns: columns
    }
    retentionInDays: 30
    totalRetentionInDays: 30
  }
}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: dceName
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      '${streamName}': {
        columns: columns
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'law-destination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          streamName
        ]
        destinations: [
          'law-destination'
        ]
        outputStream: streamName
      }
    ]
  }
  dependsOn: [
    customTable
  ]
}

output dceId string = dce.id
output dceLogsIngestionEndpoint string = dce.properties.logsIngestion.endpoint
output dcrId string = dcr.id
output dcrImmutableId string = dcr.properties.immutableId
