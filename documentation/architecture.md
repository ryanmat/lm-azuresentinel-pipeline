# Architecture: LM LogAlert → Azure Sentinel

## Data flow

```
┌──────────────────────┐   HTTPS POST     ┌──────────────────┐  EH trigger   ┌──────────────────┐
│ LogicMonitor         │   (SAS header)   │ Event Hub        │  (cardinality │ Azure Function   │
│  LogAlert Group      ├─────────────────▶│  ehns-lmsent-poc │   one)        │  func-lmsent-poc │
│  + Alert Rule        │   JSON body      │  hub: lm-alerts  ├──────────────▶│  Python 3.12     │
│  + Escalation Chain  │                  │  (1 TU Standard) │               │  Consumption Y1  │
│  + HTTP Delivery     │                  └──────────────────┘               └────────┬─────────┘
└──────────────────────┘                                                              │
                                                                                      │ System-Assigned MI
                                                                                      │  (Monitoring Metrics Publisher)
                                                                                      ▼
                                                              ┌───────────────────────────────────┐
                                                              │ Data Collection Endpoint (DCE)    │
                                                              │   + Data Collection Rule (DCR)    │
                                                              │   stream: Custom-LogicMonitor...  │
                                                              └───────────────┬───────────────────┘
                                                                              ▼
                                                              ┌───────────────────────────────────┐
                                                              │ Log Analytics Workspace           │
                                                              │   law-lmsent-poc                  │
                                                              │   Sentinel onboarded              │
                                                              │   Table: LogicMonitorAlerts_CL    │
                                                              │   Sentinel Analytics Rule (S2)    │
                                                              └───────────────────────────────────┘
```

## Auth model

| Hop | Mechanism | Why |
|---|---|---|
| LM → Event Hub | SAS token in `Authorization` header (Send-only policy `lm-send` on the hub) | LM's HTTP Delivery cannot acquire Azure AD tokens, and SAS is the supported Event Hub REST auth |
| Function → Event Hub (trigger) | System-Assigned MI + `Azure Event Hubs Data Receiver` role on the hub | Avoids storing connection strings in app settings |
| Function → Logs Ingestion API | Same MI + `Monitoring Metrics Publisher` role on the DCR | Standard MI auth for the DCE/DCR path |
| Function → Storage (runtime state) | Storage account key in `AzureWebJobsStorage` | MI-based `AzureWebJobsStorage` is not GA on classic Consumption Y1 — revisit on Flex Consumption |

SAS token is generated post-provision via `./scripts/generate_eh_sas.sh` with a 2-year expiry and pasted into the LM HTTP Delivery integration header.

## Resource inventory (all in `CTA_LM_Sentinel_POC`)

| Kind | Name | Notes |
|---|---|---|
| Resource group | `CTA_LM_Sentinel_POC` | Teardown unit (`az group delete`) |
| Log Analytics Workspace | `law-lmsent-poc` | `PerGB2018`, 30d retention, Sentinel onboarded |
| Event Hub namespace | `ehns-lmsent-poc-<uniq>` | Standard tier, 1 TU |
| Event Hub | `lm-alerts` | 2 partitions, 1d retention |
| EH auth rule (Send) | `lm-send` | LM integration uses this |
| EH auth rule (Listen) | `function-listen` | Kept for diagnostic fallback; runtime uses MI |
| Storage account | `stlmsentpoc<uniq>` | Function backing store |
| App Insights | `appi-lmsent-poc` | Workspace-based on `law-lmsent-poc` |
| App Service Plan | `plan-lmsent-poc` | Linux Consumption Y1 (eastus had zero App Service quota; moved to eastus2) |
| Function App | `func-lmsent-poc-<uniq>` | Python 3.12, System-Assigned MI |
| Data Collection Endpoint | `dce-lmsent-poc` | Logs Ingestion endpoint |
| Data Collection Rule | `dcr-lmsent-poc` | Maps stream → custom table |
| Custom table | `LogicMonitorAlerts_CL` | 19 columns, normalized schema |
| Role assignment | MI → `Azure Event Hubs Data Receiver` on hub | Trigger auth |
| Role assignment | MI → `Monitoring Metrics Publisher` on DCR | Ingest auth |

## Custom table schema: `LogicMonitorAlerts_CL`

| Column | Type | Source token | Notes |
|---|---|---|---|
| `TimeGenerated` | datetime | derived from `##START##` | Required by Azure Monitor |
| `LmAlertId` | string | `##ALERTID##` | e.g. `LMD123456` |
| `AlertType` | string | `##ALERTTYPE##` | Value TBD for LogAlert (verify live) |
| `Severity` | string | `##LEVEL##` | Critical/Error/Warning/Info |
| `Status` | string | `##ALERTSTATUS##` | active/cleared/ack |
| `DeviceName` | string | `##HOST##` | |
| `DeviceDisplayName` | string | `##HOSTNAME##` | |
| `DeviceGroups` | string | `##HOSTGROUP##` | Comma-joined path |
| `DataSourceOrGroup` | string | `##DATASOURCE##` | For LogAlerts this is the LogAlert Group name |
| `InstanceName` | string | `##INSTANCE##` | Usually empty for LogAlerts |
| `DataPointName` | string | `##DATAPOINT##` | Usually empty for LogAlerts |
| `DataPointValue` | string | `##VALUE##` | |
| `ThresholdValue` | string | `##THRESHOLD##` | |
| `AlertMessage` | string | `##MESSAGE##` | Matched log line rendering for LogAlerts |
| `StartedTime` | datetime | `##START##` | Epoch converted to datetime |
| `ClearedTime` | datetime | `##CLEARVALUE##` | Nullable |
| `AckUser` | string | `##ACKEDBY##` | Nullable |
| `PortalUrl` | string | `##ALERTDETAILURL##` | Direct link back to LM |
| `RawAlert` | dynamic | entire payload | Overflow for anything not mapped |

Stream name in the DCR: `Custom-LogicMonitorAlerts_CL`.

## Session split

- **Session 1 (this PR):** infrastructure foundation. All Bicep, deploy/teardown/SAS scripts, Function skeleton that only logs receipt.
- **Session 2 (next PR):** full Function transform + Logs Ingestion client, Sentinel analytics rule, LM-side automation (integration, escalation chain, alert rule via MCP), e2e smoke test, customer demo doc.

## Open questions (resolved in Session 2 via live webhook capture)

1. Actual `##ALERTTYPE##` value for a fired LogAlert — suspected `alert` or `logAlert`.
2. Whether Pipeline Alerts (output of Log Processing Pipelines) route through standard escalation chains or are isolated to the pipelines view. POC explicitly targets LogAlert Groups, not Pipeline Alerts.
3. Whether `##MESSAGE##` for a LogAlert contains the full matched log line or a truncated rendering.

## Known constraints

- **LogAlert Group limits:** 20 groups max per portal, 55 alerts per group, 90 alerts/min per group.
- **Event Hub Standard 1 TU:** 1 MB/s ingress, 2 MB/s egress. Far above LogAlert Group cap.
- **Logs Ingestion API ingestion latency:** typically <1 min but can be up to 5 min during heavy load.
- **Sentinel Analytics Rules (scheduled):** minimum 5-minute frequency. Not a near-real-time trigger — document this in the demo script.
- **Log Analytics Workspace soft-delete:** 14 days unless `--force true` is used (teardown.sh does this).
