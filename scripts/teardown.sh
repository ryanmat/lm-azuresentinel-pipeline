#!/usr/bin/env bash
# Description: Tear down the full POC by deleting the resource group.
# Description: Also force-purges the Log Analytics Workspace so the name is reusable immediately.

set -euo pipefail

RG="${RG:-CTA_LM_Sentinel_POC}"
WORKSPACE="${WORKSPACE:-law-lmsent-poc}"

echo "[teardown] Target RG: ${RG}"
echo "[teardown] Target workspace: ${WORKSPACE}"

if ! az group show -n "${RG}" &>/dev/null; then
  echo "[teardown] Resource group ${RG} does not exist. Nothing to do."
  exit 0
fi

# Force-purge the workspace first so the name is not held in soft-delete for 14 days.
if az monitor log-analytics workspace show -g "${RG}" -n "${WORKSPACE}" &>/dev/null; then
  echo "[teardown] Force-purging workspace ${WORKSPACE}"
  az monitor log-analytics workspace delete \
    -g "${RG}" -n "${WORKSPACE}" \
    --force true --yes \
    --output none
else
  echo "[teardown] Workspace ${WORKSPACE} not present in ${RG}"
fi

echo "[teardown] Deleting resource group ${RG} (async)"
az group delete -n "${RG}" --yes --no-wait

echo "[teardown] Delete initiated. Poll with:"
echo "  az group exists -n ${RG}"
