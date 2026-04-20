# LogicMonitor-side setup

The Azure side is fully automated (Bicep + `scripts/deploy.sh`). The LogicMonitor side has one manual step — creating the Custom HTTP Delivery integration — because the LM MCP does not expose a tool for HTTP Delivery integration creation and no LM API credentials are configured for this session.

Everything downstream of that (escalation chain + alert rule) is automated via LM MCP calls documented below.

## Step 1 — Generate the Event Hub SAS token

```bash
RG=CTA_LM_Sentinel_POC ./scripts/generate_eh_sas.sh
```

This prints the URL, method, and `Authorization` header to paste into the LM integration form. The token expires in 2 years by default; override with `EXPIRY_DAYS=N`.

## Step 2 — Create the Custom HTTP Delivery integration (UI, ~2 min)

1. In the LM portal, go to **Settings** → **Integrations** → **+ Add** → **Custom HTTP Delivery**.
2. Fill in:
   - **Name:** `Azure Sentinel Pipeline (POC)`
   - **Description:** `Routes alerts to Event Hub for Sentinel ingestion (POC, teardown 2026-05-31)`
   - **URL:** the URL printed by `generate_eh_sas.sh` (e.g. `https://ehns-lmsent-poc-<uniq>.servicebus.windows.net/lm-alerts/messages`)
   - **HTTP method:** `POST`
   - **Alert data format:** **JSON Format**
   - **Alert data (JSON body):** paste the contents of [`payload_template.json`](./payload_template.json) — all tokens are LM-native `##TOKENS##` and will be substituted per alert.
3. Under **HTTP headers**, add two rows:
   - `Authorization` = the `SharedAccessSignature ...` value from the SAS script output
   - `Content-Type` = `application/json`
4. Under **Alert Event**, leave all three events checked (Active, Acknowledged, Cleared) so we capture the full lifecycle in Sentinel.
5. Click **Test Alert Delivery** and confirm a green checkmark. A test event should land in Event Hub (visible via `az eventhubs eventhub show` message count or in App Insights via the Function's trace).
6. Save. Note the integration ID shown in the URL after save (looks like `?integrationId=N` or in the details pane) — we reference it in step 3.

## Step 3 — Escalation chain + alert rule (automated via LM MCP)

These objects are created via LM MCP calls documented here for reproducibility. The Claude Code session that first sets up the POC runs these in-session. The resulting IDs are recorded at the bottom of this file.

```
# Escalation chain (wraps the integration in step 2)
create_escalation_chain(
  name="Azure Sentinel Pipeline (POC)",
  description="Routes LM alerts into the Azure Sentinel POC via EH",
  enable_throttling=false,
  destinations=[{
    "stageNumber": 1,
    "rcpts": [{
      "method": "integration",
      "type": "ADMIN",
      "addr": "<HTTP_DELIVERY_INTEGRATION_ID_FROM_STEP_2>"
    }]
  }]
)

# Alert rule (scopes which alerts route to the chain above)
create_alert_rule(
  name="Route test-device alerts to Azure Sentinel POC",
  priority=5,
  escalation_chain_id=<ID_FROM_create_escalation_chain>,
  devices=["petclinic-vm"],
  level_str="All",
  suppress_alert_clear=false,
  suppress_alert_ack_sdt=false
)
```

## Step 4 — Verify

1. Wait for the test device to fire an alert that matches the rule (or force one by tightening a threshold).
2. In Azure, run:
   ```
   az monitor app-insights query --app <app-id> --analytics-query \
     "traces | where timestamp > ago(10m) and message has 'LM alert received' | take 5"
   ```
3. Confirm the trace shows the alert metadata. Session 2 extends this to `LogicMonitorAlerts_CL | where LmAlertId == '<id>'`.

## Teardown

Run the inverse (automated via MCP from the closing session, or manually via UI):
- Delete the alert rule
- Delete the escalation chain
- Delete the HTTP Delivery integration

The SAS token on the EH auto-expires after the configured period (default 2 years). If the EH namespace is destroyed via `./scripts/teardown.sh`, the token becomes useless immediately regardless of expiry.

## Actual IDs (filled in at setup time)

```
HTTP Delivery integration ID: <filled in by Ryan after step 2>
Escalation chain ID:          <filled in by MCP call in step 3>
Alert rule ID:                <filled in by MCP call in step 3>
Test device:                  <filled in after rule is saved>
```
