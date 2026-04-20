# Project Lessons: lm-azuresentinel-pipeline

Project-specific learned behaviors. Global lessons live in `~/.claude/docs/lessons.md`.

Append to this file at session close-out. Each lesson: one-line rule, **Why:** line (incident/reason), **How to apply:** line (when it kicks in).

## LogicMonitor integration

_(No lessons recorded yet.)_

## Azure Sentinel / Logs Ingestion

- Modern Sentinel onboarding via `Microsoft.SecurityInsights/onboardingStates` still produces a legacy `Microsoft.OperationsManagement/solutions` resource named `SecurityInsights(<workspace>)`. **Why:** Internal implementation still creates the solution artifact for backwards compatibility. **How to apply:** When verifying Sentinel onboarding via `az resource list`, the solution resource IS the evidence — don't interpret its presence as legacy/incorrect provisioning.
- App Insights creates an implicit `microsoft.alertsmanagement/smartDetectorAlertRules` resource (`Failure Anomalies - <appinsights-name>`) automatically when a component is provisioned. **Why:** Default smart-detection rule, benign. **How to apply:** Expect resource count to be N+1 where N is what Bicep declares. Don't flag it as drift.

## Event Hub + Function

- `func azure functionapp publish` fails on WSL/Ubuntu-slim with ICU/globalization errors unless `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` is exported. **Why:** The .NET runtime inside `func` requires ICU libraries for culture-aware JSON deserialization; WSL default rootfs lacks them. **How to apply:** Always set `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` before invoking `func publish` on Linux dev environments. Deploy script does this automatically.
- `az functionapp deployment source config-zip` can return a false `ResourceNotFound` error immediately after Function App creation even when `az functionapp show` succeeds on the same resource. **Why:** The SCM-site endpoint that `config-zip` hits propagates separately from the Microsoft.Web/sites resource provider; there is a several-minute gap. **How to apply:** Prefer `func azure functionapp publish --build remote` with ICU workaround for deploys immediately after `az deployment group create`. Zip deploy via az CLI only reliably works after a several-minute warm-up.
- Event Hub trigger binding uses `%ENV_VAR_NAME%` syntax in the decorator to resolve the hub name at trigger attach time (e.g. `event_hub_name="%EVENT_HUB_NAME%"`). **Why:** Python decorators evaluate at module import, before app settings are guaranteed to be in `os.environ` for the host process. `%...%` is the Azure Functions binding expression that resolves at host startup. **How to apply:** Use `%...%` for any binding property that must read an app setting. Never read `os.environ` inside `@app.event_hub_message_trigger(...)` decorator arguments.

## LM MCP usage patterns

_(No lessons recorded yet.)_

## Bicep and infra

- Azure subscription App Service quota can be 0 per-region across ALL tiers (Dynamic/Basic/Standard). **Why:** Sandbox / cost-controlled subscriptions often have hard-capped App Service VM quotas. The CTA sub has 0 quota in East US for every App Service tier, but existing plans in East US 2 imply that region has quota. **How to apply:** Before picking a region for a new Function App deployment, either (a) check with `az appservice plan list` which regions already have active plans on the subscription, or (b) run `az deployment group what-if` to catch quota issues before the real deploy. Do not assume "my favorite region" works.
- `az bicep build` produces a nested ARM JSON file as `main.json` alongside `.bicep` templates when using `--outdir` — leftover files can pollute git. **Why:** The JSON output is a build artifact, not source. **How to apply:** `.gitignore` includes `main.json` and `*.json.bak` for this reason. Never commit ARM JSON that was compiled from Bicep.
- `dependsOn` in Bicep is needed when a child resource references a parent resource via `existing` AND the parent is created by another module call. **Why:** Bicep's implicit dependency analyzer only follows direct resource references, not cross-module `existing` lookups. **How to apply:** When a module calls `existing` on a resource that was created by another module, either (a) add an explicit `dependsOn` in the parent `main.bicep` module call, or (b) pass the output of the creator module as a param to avoid the `existing` lookup.
