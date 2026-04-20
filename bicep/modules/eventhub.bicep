// Description: Event Hub namespace and hub for LM webhook landing pad.
// Description: Creates Standard-tier 1 TU namespace, single hub, and two auth rules (Send for LM, Listen for Function).

targetScope = 'resourceGroup'

@description('Azure region.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Event Hub namespace name.')
param namespaceName string

@description('Event Hub name.')
param eventHubName string

@description('Partition count for the hub.')
param partitionCount int = 2

@description('Message retention in days (POC scale).')
param messageRetentionDays int = 1

resource namespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    isAutoInflateEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource hub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: namespace
  name: eventHubName
  properties: {
    partitionCount: partitionCount
    messageRetentionInDays: messageRetentionDays
  }
}

resource sendRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: hub
  name: 'lm-send'
  properties: {
    rights: [
      'Send'
    ]
  }
}

resource receiveRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: hub
  name: 'function-listen'
  properties: {
    rights: [
      'Listen'
    ]
  }
}

output namespaceName string = namespace.name
output namespaceId string = namespace.id
output hubId string = hub.id
output sendRuleName string = sendRule.name
output sendRuleId string = sendRule.id
output receiveRuleName string = receiveRule.name
output receiveRuleId string = receiveRule.id
