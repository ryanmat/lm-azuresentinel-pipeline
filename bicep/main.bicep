// Description: Orchestrator Bicep for the LM LogAlert -> Azure Sentinel POC.
// Description: Wires workspace, event hub, DCR, and Function App modules into a single deployment.

targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short project prefix, lowercase alphanumeric and hyphens.')
param prefix string = 'lmsent-poc'

@description('Tags applied to every resource.')
param tags object = {
  poc: 'lm-sentinel'
  owner: 'ryan'
}

@description('Event Hub name that receives LM webhook payloads.')
param eventHubName string = 'lm-alerts'

@description('Custom Log Analytics table name. Must end with _CL.')
param customTableName string = 'LogicMonitorAlerts_CL'

var uniq = toLower(uniqueString(resourceGroup().id))
var storagePrefix = replace(replace(prefix, '-', ''), '_', '')
var storageName = take('st${storagePrefix}${uniq}', 24)
var functionAppName = 'func-${prefix}-${uniq}'
var planName = 'plan-${prefix}'
var appInsightsName = 'appi-${prefix}'
var workspaceName = 'law-${prefix}'
var ehNamespaceName = 'ehns-${prefix}-${uniq}'
var dceName = 'dce-${prefix}'
var dcrName = 'dcr-${prefix}'
var streamName = 'Custom-${customTableName}'

module workspace 'modules/workspace.bicep' = {
  name: 'workspace-deploy'
  params: {
    location: location
    tags: tags
    workspaceName: workspaceName
  }
}

module eventhub 'modules/eventhub.bicep' = {
  name: 'eventhub-deploy'
  params: {
    location: location
    tags: tags
    namespaceName: ehNamespaceName
    eventHubName: eventHubName
  }
}

module dcr 'modules/dcr.bicep' = {
  name: 'dcr-deploy'
  params: {
    location: location
    tags: tags
    dceName: dceName
    dcrName: dcrName
    workspaceId: workspace.outputs.workspaceId
    workspaceName: workspace.outputs.workspaceName
    customTableName: customTableName
    streamName: streamName
  }
}

module functionApp 'modules/function.bicep' = {
  name: 'function-deploy'
  params: {
    location: location
    tags: tags
    planName: planName
    functionAppName: functionAppName
    storageName: storageName
    appInsightsName: appInsightsName
    workspaceId: workspace.outputs.workspaceId
    eventHubNamespaceName: eventhub.outputs.namespaceName
    eventHubName: eventHubName
    eventHubAuthRuleName: eventhub.outputs.receiveRuleName
    dceEndpoint: dcr.outputs.dceLogsIngestionEndpoint
    dcrImmutableId: dcr.outputs.dcrImmutableId
    dcrId: dcr.outputs.dcrId
    streamName: streamName
  }
}

output workspaceId string = workspace.outputs.workspaceId
output workspaceCustomerId string = workspace.outputs.customerId
output workspaceName string = workspace.outputs.workspaceName
output eventHubNamespace string = eventhub.outputs.namespaceName
output eventHubName string = eventHubName
output eventHubSendRuleName string = eventhub.outputs.sendRuleName
output dceEndpoint string = dcr.outputs.dceLogsIngestionEndpoint
output dcrImmutableId string = dcr.outputs.dcrImmutableId
output streamName string = streamName
output functionAppName string = functionApp.outputs.functionAppName
output functionPrincipalId string = functionApp.outputs.principalId
