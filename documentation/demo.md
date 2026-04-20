# Customer demo: LM → Azure Sentinel POC

A 10-minute walkthrough that proves LogicMonitor alerts can land as Microsoft Sentinel incidents via Event Hub + Azure Function, and gives enough operational texture for the customer to scope their real build.

## Audience and goal

The customer is considering **Azure Event Hub + Azure Function** as the bridge between LM alerts and Microsoft Sentinel, specifically for LM **Log Alerts**. This POC demonstrates:

- The full data path works end-to-end with representative LM alert payloads
- Managed Identity handles all Azure-side auth (no long-lived secrets beyond the LM-side SAS)
- A Sentinel Analytics Rule raises incidents on critical alerts automatically
- The whole thing is disposable (one `az group delete` tears it down)

## What we built

```
LM HTTP Delivery integration
      │  (SAS in Authorization header)
      ▼
Azure Event Hub (Standard, 1 TU) buffer
      │  (System-Assigned MI)
      ▼
Azure Function (Python 3.12, EH trigger)
      │  (same MI + Monitoring Metrics Publisher on DCR)
      ▼
Data Collection Endpoint + Data Collection Rule
      │
      ▼
Log Analytics Workspace: LogicMonitorAlerts_CL table (19 normalized columns)
      │
      ▼
Microsoft Sentinel Analytics Rule: "LM Critical Alert -> Sentinel Incident"
```

## Demo flow (10 min)

### 1. Show the LM configuration (2 min)

In the LM portal:
- **Integrations** → "Azure Sentinel Pipeline (POC)" → show URL (Event Hub), custom `Authorization` header with SAS, JSON body template with `##tokens##`
- **Escalation Chains** → "Azure Sentinel Pipeline POC" → single stage routing to the integration via Ryan's user account
- **Alert Rules** → "Route openclaw-vm alerts to Azure Sentinel POC" → scoped to `openclaw-vm*` devices, all severities

Key message: *no LM-side custom code. Standard LM primitives (integration, chain, rule) do the routing.*

### 2. Fire a synthetic alert and watch it flow (3 min)

```bash
./scripts/e2e_smoke_test.sh
```

The script:
1. Builds a realistic LM alert JSON payload
2. Generates a fresh SAS token and POSTs to Event Hub (HTTP 201)
3. Polls `LogicMonitorAlerts_CL` until the row appears

Expected total latency: **60-90 seconds** from Event Hub ingress to Log Analytics queryable.

### 3. Show the ingested row in the Azure portal (2 min)

In the Azure portal → Log Analytics workspace `law-lmsent-poc` → Logs:

```kql
LogicMonitorAlerts_CL
| where TimeGenerated > ago(15m)
| project TimeGenerated, LmAlertId, Severity, Status, DeviceName, DataSourceOrGroup, AlertMessage, PortalUrl
| order by TimeGenerated desc
```

Click into a row to show:
- **Normalized columns** — Severity, DeviceName, DataSourceOrGroup are structured fields, queryable directly
- **RawAlert dynamic column** — full original LM payload preserved for anything not mapped
- **PortalUrl** — click-through back to the LM alert for investigation

Key message: *structured in Sentinel, full fidelity preserved, no reparsing needed.*

### 4. Show the Sentinel incident (2 min)

Sentinel → Incidents → Active:

Look for the incident raised by the rule "LM Critical Alert -> Sentinel Incident". Show:
- **Entity mapping** — DeviceName is mapped as Host entity, so it joins with other host-related detections
- **Timeline** — the LM alert row is attached as an alert in the incident
- **Comments / status** — incident can be assigned, triaged, closed with a resolution

Key message: *LM alerts now behave like any other Sentinel signal — SOC workflows apply.*

### 5. Teardown (1 min)

```bash
./scripts/teardown.sh
```

Everything in CTA_LM_Sentinel_POC gone. LM-side objects removed via 3 clicks in the LM portal (integration, chain, rule). Back to zero in under 3 minutes.

Key message: *disposable by design. Customer can reproduce this on their subscription from the Bicep template in this repo.*

## Talking points for Q&A

| Question | Answer |
|---|---|
| Does this work for LM **Log Alerts** specifically? | Yes. LM HTTP Delivery is uniform across alert types. `##ALERTTYPE##` = `alert` for both datapoint and log alerts; use `##DATASOURCE##` (which holds the LogAlert Group name for log alerts) to distinguish. The Function's transform is alert-type agnostic. |
| What about alert volume? | LogAlert Groups cap at 90 alerts/min per group. Event Hub Standard 1 TU handles 1 MB/s ingress (~1000 alerts/sec at 1KB each). Function Consumption Y1 scales horizontally automatically. Sentinel ingestion is typically <5 min latency. The bottleneck is LM's per-group cap, not the Azure side. |
| Authentication / secrets management? | LM → Event Hub uses a SAS token with Send-only rights (rotate every 1-2 years or on breach). Everything Azure-side uses Managed Identity: no stored credentials. |
| Cost at production volume? | Dominated by Sentinel/Log Analytics GB ingested, ~$2.30/GB ingestion + $2/GB Sentinel. At 1000 alerts/hr @ 3KB each, that's ~2GB/month = ~$9/mo Azure-side. Event Hub Standard 1 TU is ~$11/mo flat. Function Consumption is near-free at this volume. |
| Can we route MULTIPLE LM portals into one Sentinel? | Yes. Each LM portal gets its own HTTP Delivery integration (its own SAS), all POSTing to the same Event Hub. Function already namespaces rows by `DeviceName` and preserves full `RawAlert`; add a `LmPortalName` column to the DCR if you want portal-level filtering. |
| Can alerts be ack'd/cleared in LM from Sentinel? | Not in this POC. LM's HTTP Delivery is one-way. Bidirectional sync would require adding an Azure Logic App or Function that calls LM's API to update alert status when Sentinel incidents close. Scope for phase 2. |

## What this POC does NOT demonstrate

- **LogAlert Group setup** — creating the actual LogAlert Group that detects patterns in ingested logs. The POC routes alerts from an existing alert rule scoped to `openclaw-vm`. For the customer's real deployment, they configure LogAlert Groups on their LM portal exactly as they would today; our pipeline picks up whatever they produce.
- **Multi-region deployment** — single-region `eastus2`. Customer can deploy the Bicep template to any region that has Event Hub + DCR support.
- **SIEM correlation rules beyond severity** — we raise incidents for any critical LM alert. Real deployments would build topic-specific analytics rules (auth failures, privilege escalation patterns, etc.) on top of the base table.
- **High-volume performance tuning** — Event Hub Standard 1 TU and Consumption Y1 cover POC-scale. At >1000 alerts/sec sustained, tune partition count, switch to Premium, and batch EH trigger (`cardinality="many"`).

## Next steps for the customer

1. Deploy the Bicep in their own Azure subscription
2. Create their own HTTP Delivery integration in their LM portal pointing at their Event Hub
3. Scope their alert rules to route the alert categories they care about (starting with critical log alerts)
4. Tune the Sentinel analytics rule KQL to match their incident creation policy
5. Iterate on `LogicMonitorAlerts_CL` schema if additional LM fields become relevant
