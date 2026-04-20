#!/usr/bin/env bash
# Description: End-to-end pipeline smoke test. Sends a synthetic LM alert through Event Hub
# Description: and waits until the corresponding row appears in LogicMonitorAlerts_CL.

set -euo pipefail

RG="${RG:-CTA_LM_Sentinel_POC}"
NAMESPACE="${NAMESPACE:-}"
HUB="${HUB:-lm-alerts}"
POLICY="${POLICY:-lm-send}"
WORKSPACE="${WORKSPACE:-law-lmsent-poc}"
TIMEOUT_SEC="${TIMEOUT_SEC:-600}"

if [[ -z "${NAMESPACE}" ]]; then
  NAMESPACE=$(az eventhubs namespace list -g "${RG}" --query "[?starts_with(name, 'ehns-lmsent-poc')] | [0].name" -o tsv)
fi

TEST_ID="e2e-$(date +%s)-$RANDOM"
NOW_EPOCH=$(date +%s)

PAYLOAD=$(cat <<EOF
{"alertId":"${TEST_ID}","alertType":"alert","severity":"critical","status":"active","deviceName":"smoke-test-device","deviceDisplayName":"smoke-test-device","deviceGroups":"/Tests","dataSourceOrGroup":"Synthetic","instanceName":"eh-trigger","dataPointName":"RoundTrip","dataPointValue":"1.0","thresholdValue":"> 0","alertMessage":"e2e smoke test ${TEST_ID}","startEpoch":"${NOW_EPOCH}","clearEpoch":"","ackUser":"","portalUrl":"https://example.com/alert/${TEST_ID}","eventSource":""}
EOF
)

echo "[smoke] Test ID: ${TEST_ID}"
echo "[smoke] Target: ${NAMESPACE}/${HUB}"

KEY=$(az eventhubs eventhub authorization-rule keys list \
  -g "${RG}" --namespace-name "${NAMESPACE}" --eventhub-name "${HUB}" --name "${POLICY}" \
  --query primaryKey -o tsv)
URI="https://${NAMESPACE}.servicebus.windows.net/${HUB}"
ENCODED_URI=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${URI}")
EXPIRY=$(( NOW_EPOCH + 3600 ))
SIG=$(printf '%s\n%s' "${ENCODED_URI}" "${EXPIRY}" | openssl dgst -sha256 -hmac "${KEY}" -binary | base64)
ENCODED_SIG=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${SIG}")
SAS="SharedAccessSignature sr=${ENCODED_URI}&sig=${ENCODED_SIG}&se=${EXPIRY}&skn=${POLICY}"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${URI}/messages" \
  -H "Authorization: ${SAS}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

if [[ "${HTTP_CODE}" != "201" ]]; then
  echo "[smoke] FAIL: Event Hub returned HTTP ${HTTP_CODE}" >&2
  exit 1
fi
echo "[smoke] EH POST: 201 (accepted)"

WORKSPACE_ID=$(az monitor log-analytics workspace show -g "${RG}" -n "${WORKSPACE}" --query customerId -o tsv)
echo "[smoke] Polling ${WORKSPACE} for row (max ${TIMEOUT_SEC}s)..."

DEADLINE=$(( NOW_EPOCH + TIMEOUT_SEC ))
until [[ $(date +%s) -ge ${DEADLINE} ]]; do
  result=$(az monitor log-analytics query --workspace "${WORKSPACE_ID}" \
    --analytics-query "LogicMonitorAlerts_CL | where LmAlertId == '${TEST_ID}' | take 1" \
    -o json 2>/dev/null || echo '[]')
  if echo "${result}" | jq -e '.[0]?' >/dev/null 2>&1; then
    echo "[smoke] PASS: row ingested"
    echo "${result}" | jq '.[0] | {LmAlertId, Severity, Status, DeviceName, DataSourceOrGroup, AlertMessage}'
    exit 0
  fi
  sleep 15
done

echo "[smoke] FAIL: row did not appear within ${TIMEOUT_SEC}s" >&2
exit 1
