# Runbook: LM → Azure Sentinel POC

Operational reference for the pipeline deployed in resource group `CTA_LM_Sentinel_POC` (region `eastus2`).

## Where things live

| Concern | Location |
|---|---|
| Function logs | App Insights component `appi-lmsent-poc` (workspace-based, under `law-lmsent-poc`) |
| Ingested alert rows | Log Analytics table `LogicMonitorAlerts_CL` on `law-lmsent-poc` |
| Sentinel incidents | `Microsoft.SecurityInsights` namespace under `law-lmsent-poc` |
| LM integration | LM portal → Settings → Integrations → "Azure Sentinel Pipeline (POC)" |
| Escalation chain | LM portal → Settings → Alert Settings → Escalation Chains → "Azure Sentinel Pipeline POC" |
| Alert rule | LM portal → Settings → Alert Settings → Alert Rules → "Route openclaw-vm alerts to Azure Sentinel POC" |

## Diagnostic queries

### "Did an alert I fired actually reach Sentinel?"

Replace `<alert-id>` with the LM alert ID (visible in the LM alert URL).

```kql
LogicMonitorAlerts_CL
| where LmAlertId == "<alert-id>"
| project TimeGenerated, LmAlertId, Severity, Status, DeviceName, DataSourceOrGroup, AlertMessage, PortalUrl
```

### "Why isn't my alert showing up?"

First check the Function did receive and process it:

```kusto
traces
| where timestamp > ago(15m) and operation_Name == "process_lm_alerts"
| project timestamp, message, severityLevel
| order by timestamp desc
```

Look for:
- `LM alert received` — Function got the EH message
- `LM alert normalized` — transform succeeded
- `Uploading 1 rows` — Logs Ingestion call made
- `Failed to transform` — transform error, check the next log line for the payload

Then check for exceptions:

```kusto
exceptions
| where timestamp > ago(15m)
| project timestamp, type, outerMessage, innermostMessage
| order by timestamp desc
```

### "What's the ingestion latency?"

```kql
LogicMonitorAlerts_CL
| where TimeGenerated > ago(1h)
| extend ingestion_delay_sec = datetime_diff('second', ingestion_time(), TimeGenerated)
| summarize p50 = percentile(ingestion_delay_sec, 50), p95 = percentile(ingestion_delay_sec, 95), n = count()
```

## Smoke test

```bash
./scripts/e2e_smoke_test.sh
```

Sends a synthetic alert through Event Hub and waits up to 10 minutes for the row to appear in `LogicMonitorAlerts_CL`. Exit code 0 = pipeline healthy.

## Common issues

### Function shows `ImportError: No module named 'pydantic'` (or similar) at startup

Remote Oryx build failed and deployed the app without resolving Python dependencies. Workaround: deploy with locally-built deps.

```bash
cd function
pip install --target=.python_packages/lib/site-packages -r requirements.txt \
  --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.12
DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 func azure functionapp publish \
  func-lmsent-poc-<uniq> --python --no-build
```

### `Authorization` SAS header returns `401 MalformedToken`

The SAS value either has whitespace issues or was mangled by form paste. Regenerate with `./scripts/generate_eh_sas.sh`, paste carefully (single space after `SharedAccessSignature`, no trailing whitespace), and test with:

```bash
curl -v -X POST "https://<ns>.servicebus.windows.net/<hub>/messages" \
  -H "Authorization: <sas>" -H "Content-Type: application/json" -d '{}'
```

Expected: `HTTP 201`.

### Sentinel incident isn't being raised

The analytics rule runs every 5 minutes. Check when it last ran:

```kql
SecurityIncident
| where Title contains "LM Critical Alert"
| project TimeGenerated, Title, Severity, Status
| order by TimeGenerated desc
| take 5
```

Also verify the rule itself is enabled: LM portal → Sentinel workspace → Analytics → Active rules → "LM Critical Alert -> Sentinel Incident".

The rule explicitly filters out `LmAlertId` starting with `e2e-` (the smoke test prefix) to avoid incident noise — e2e runs will land rows but not raise incidents.

### Function MI loses permissions

If you see `Forbidden` errors from `azure-monitor-ingestion`, the role assignments may have drifted. Verify:

```bash
PRINCIPAL=$(az functionapp show -g CTA_LM_Sentinel_POC -n func-lmsent-poc-<uniq> --query identity.principalId -o tsv)
az role assignment list --assignee $PRINCIPAL --query "[].{role:roleDefinitionName, scope:scope}" -o table
```

Expected roles:
- `Azure Event Hubs Data Receiver` on the hub
- `Monitoring Metrics Publisher` on the DCR

Re-run `./scripts/deploy.sh` to reconcile.

## Cost monitoring

```bash
az consumption usage list \
  --start-date "$(date -d '30 days ago' +%Y-%m-%d)" \
  --end-date "$(date +%Y-%m-%d)" \
  --query "[?contains(instanceName, 'lmsent-poc')].{name:instanceName, meter:meterName, cost:pretaxCost}" \
  -o table
```

Expected ~$15-20/mo while running, dominated by Event Hub Standard (1 TU).

## Teardown

```bash
./scripts/teardown.sh
```

Force-purges the workspace (reclaims the name immediately, no 14-day soft-delete hold) and deletes the resource group. Takes ~2 minutes asynchronously.

Then manually tear down the LM-side objects (MCP doesn't create HTTP Delivery integrations; see `docs/mcp-feedback.md` for details):

1. LM portal → Alert Rules → delete `Route openclaw-vm alerts to Azure Sentinel POC`
2. LM portal → Escalation Chains → delete `Azure Sentinel Pipeline POC`
3. LM portal → Integrations → delete `Azure Sentinel Pipeline (POC)`

The SAS token on the Event Hub becomes invalid the moment the EH namespace is destroyed, regardless of its stated expiry.
