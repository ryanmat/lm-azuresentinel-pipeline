using 'main.bicep'

param location = 'eastus'
param prefix = 'lmsent-poc'
param tags = {
  poc: 'lm-sentinel'
  owner: 'ryan'
  teardown: '2026-05-31'
}
param eventHubName = 'lm-alerts'
param customTableName = 'LogicMonitorAlerts_CL'
