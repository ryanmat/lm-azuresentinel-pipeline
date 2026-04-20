// Description: Microsoft Sentinel Scheduled Analytics Rule for LM critical alerts.
// Description: Fires an incident per critical LM alert row arriving in LogicMonitorAlerts_CL.

targetScope = 'resourceGroup'

@description('Name of the Log Analytics Workspace hosting Sentinel.')
param workspaceName string

@description('Display name for the analytics rule.')
param ruleDisplayName string = 'LM Critical Alert -> Sentinel Incident'

@description('Cron-ish frequency for the rule to run (ISO 8601 duration).')
param queryFrequency string = 'PT5M'

@description('Lookback window for each rule evaluation (ISO 8601 duration). Should be >= queryFrequency.')
param queryPeriod string = 'PT10M'

@description('Severity of the Sentinel incident raised.')
@allowed([
  'Informational'
  'Low'
  'Medium'
  'High'
])
param incidentSeverity string = 'High'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource rule 'Microsoft.SecurityInsights/alertRules@2024-03-01' = {
  scope: workspace
  name: guid(workspace.id, 'lm-critical-alert-rule')
  kind: 'Scheduled'
  properties: {
    displayName: ruleDisplayName
    description: 'Raises a Sentinel incident whenever LogicMonitor emits a critical active alert. Filters out synthetic e2e test traffic.'
    severity: incidentSeverity
    enabled: true
    query: '''
LogicMonitorAlerts_CL
| where Severity =~ "critical"
| where Status =~ "active"
| where not(LmAlertId startswith "e2e-")
| where not(Status =~ "test")
| project TimeGenerated, LmAlertId, Severity, Status, DeviceName, DataSourceOrGroup, AlertMessage, PortalUrl
'''
    queryFrequency: queryFrequency
    queryPeriod: queryPeriod
    triggerOperator: 'GreaterThan'
    triggerThreshold: 0
    suppressionDuration: 'PT5H'
    suppressionEnabled: false
    tactics: [
      'Discovery'
    ]
    incidentConfiguration: {
      createIncident: true
      groupingConfiguration: {
        enabled: true
        reopenClosedIncident: false
        lookbackDuration: 'PT1H'
        matchingMethod: 'AnyAlert'
      }
    }
    eventGroupingSettings: {
      aggregationKind: 'AlertPerResult'
    }
    entityMappings: [
      {
        entityType: 'Host'
        fieldMappings: [
          {
            identifier: 'HostName'
            columnName: 'DeviceName'
          }
        ]
      }
    ]
  }
}

output ruleId string = rule.id
output ruleName string = rule.name
