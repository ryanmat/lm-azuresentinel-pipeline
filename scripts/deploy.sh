#!/usr/bin/env bash
# Description: Deploy the LM -> Sentinel POC infrastructure.
# Description: Creates resource group, runs Bicep, then publishes Function code if present.

set -euo pipefail

RG="${RG:-CTA_LM_Sentinel_POC}"
LOCATION="${LOCATION:-eastus}"
DEPLOYMENT_NAME="lm-sentinel-poc-$(date -u +%Y%m%d-%H%M%S)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[deploy] Using subscription: $(az account show --query name -o tsv)"
echo "[deploy] Target RG: ${RG}"
echo "[deploy] Location: ${LOCATION}"

if ! az group show -n "${RG}" &>/dev/null; then
  echo "[deploy] Creating resource group ${RG}"
  az group create -n "${RG}" -l "${LOCATION}" --tags poc=lm-sentinel owner=ryan >/dev/null
else
  echo "[deploy] Resource group ${RG} already exists"
fi

echo "[deploy] Running Bicep deployment ${DEPLOYMENT_NAME}"
az deployment group create \
  --resource-group "${RG}" \
  --name "${DEPLOYMENT_NAME}" \
  --template-file "${REPO_ROOT}/bicep/main.bicep" \
  --parameters "${REPO_ROOT}/bicep/main.bicepparam" \
  --output none

echo "[deploy] Collecting outputs"
OUTPUTS_JSON=$(az deployment group show -g "${RG}" -n "${DEPLOYMENT_NAME}" --query properties.outputs -o json)
FUNCTION_APP=$(echo "${OUTPUTS_JSON}" | jq -r '.functionAppName.value')
EH_NAMESPACE=$(echo "${OUTPUTS_JSON}" | jq -r '.eventHubNamespace.value')
EH_HUB=$(echo "${OUTPUTS_JSON}" | jq -r '.eventHubName.value')
DCE_ENDPOINT=$(echo "${OUTPUTS_JSON}" | jq -r '.dceEndpoint.value')
DCR_IMMUTABLE=$(echo "${OUTPUTS_JSON}" | jq -r '.dcrImmutableId.value')
STREAM_NAME=$(echo "${OUTPUTS_JSON}" | jq -r '.streamName.value')

echo ""
echo "[deploy] ==== Deployment summary ===="
echo "  Function App:     ${FUNCTION_APP}"
echo "  Event Hub NS:     ${EH_NAMESPACE}"
echo "  Event Hub:        ${EH_HUB}"
echo "  DCE endpoint:     ${DCE_ENDPOINT}"
echo "  DCR immutable ID: ${DCR_IMMUTABLE}"
echo "  Stream:           ${STREAM_NAME}"
echo ""

# Publish Function code if the source tree has a pyproject and a function_app.py
if [[ -f "${REPO_ROOT}/function/function_app.py" ]]; then
  echo "[deploy] Publishing Function code from ${REPO_ROOT}/function"
  if ! command -v func &>/dev/null; then
    echo "[deploy] WARNING: 'func' (Azure Functions Core Tools) not found on PATH — skipping publish."
    echo "[deploy] Install with: npm i -g azure-functions-core-tools@4"
  else
    (cd "${REPO_ROOT}/function" && func azure functionapp publish "${FUNCTION_APP}" --python --build remote)
  fi
else
  echo "[deploy] No function/function_app.py found — skipping Function publish (skeleton deploys later)"
fi

echo "[deploy] Done."
