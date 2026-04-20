# lm-azuresentinel-pipeline

POC that routes LogicMonitor **LogAlerts** into **Azure Sentinel** via Event Hub and an Azure Function, using the Logs Ingestion API and a custom normalized table.

## What it does

```
LM LogAlert Group --(HTTP Delivery, SAS)--> Event Hub --> Azure Function --(MI + DCR)--> Log Analytics / Sentinel
```

1. A LogicMonitor LogAlert fires (regex/keyword/KV match on ingested logs).
2. The escalation chain routes it through a Custom HTTP Delivery integration that POSTs JSON to an Azure Event Hub using a SAS token.
3. An Azure Function is triggered off the hub, transforms the payload into a normalized schema, and POSTs to the Logs Ingestion API via a Data Collection Endpoint + Data Collection Rule.
4. The DCR writes rows to a custom table `LogicMonitorAlerts_CL` on a Sentinel-enabled Log Analytics workspace.
5. A Sentinel Analytics Rule raises an incident when a critical LM alert appears.

See `documentation/architecture.md` for the full diagram, auth model, and resource inventory.

## Quick start

Prerequisites:
- `az` authenticated against the target subscription (Customer Technical Architects)
- Azure Functions Core Tools (`func`) on PATH for Function deploy
- `uv` for local Python dev
- `jq` and `openssl` for the SAS helper script

```bash
# Deploy infrastructure + Function code
./scripts/deploy.sh

# Generate the SAS token LM will use in its HTTP Delivery integration
./scripts/generate_eh_sas.sh

# Tear it all down when done
./scripts/teardown.sh
```

Environment overrides: `RG`, `LOCATION`, `NAMESPACE`, `HUB`, `POLICY`, `EXPIRY_DAYS`.

## Layout

| Path | What |
|---|---|
| `bicep/` | IaC: main orchestrator, modules for workspace, eventhub, dcr, function |
| `function/` | Python 3.12 Azure Function (uv, pytest) |
| `logicmonitor/` | LM-side setup: HTTP Delivery payload template and MCP automation (Session 2) |
| `scripts/` | deploy, teardown, SAS generator, e2e smoke test (Session 2) |
| `documentation/` | architecture doc, runbook, customer demo script |
| `docs/lessons.md` | Project-specific learned behaviors |

## Cost

~$15-20/mo while running, dominated by Event Hub Standard (1 TU). $0 after `./scripts/teardown.sh`.

## Teardown discipline

Every resource lives in `CTA_LM_Sentinel_POC` (dedicated). `teardown.sh` force-purges the Log Analytics Workspace so the name is immediately reusable and then deletes the resource group. Nothing in `CTA_Resource_Group` or any other RG is touched.
