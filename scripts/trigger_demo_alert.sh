#!/usr/bin/env bash
# Description: Fire a single synthetic critical alert that the Sentinel Analytics Rule WILL pick up.
# Description: Uses a demo- prefix (not e2e-) so the rule's filter admits it and an incident is created.

set -euo pipefail

RG="${RG:-CTA_LM_Sentinel_POC}"
NAMESPACE="${NAMESPACE:-}"
HUB="${HUB:-lm-alerts}"
POLICY="${POLICY:-lm-send}"

if [[ -z "${NAMESPACE}" ]]; then
  NAMESPACE=$(az eventhubs namespace list -g "${RG}" --query "[?starts_with(name, 'ehns-lmsent-poc')] | [0].name" -o tsv)
fi

TEST_ID="demo-$(date +%s)"
NOW_EPOCH=$(date +%s)

PAYLOAD=$(cat <<EOF
{"alertId":"${TEST_ID}","alertType":"alert","severity":"critical","status":"active","deviceName":"openclaw-vm","deviceDisplayName":"openclaw-vm","deviceGroups":"/Servers/Linux","dataSourceOrGroup":"Demo DataSource","instanceName":"demo-instance","dataPointName":"SimulatedMetric","dataPointValue":"9999","thresholdValue":"> 100","alertMessage":"Demo critical alert (triggered by scripts/trigger_demo_alert.sh)","startEpoch":"${NOW_EPOCH}","clearEpoch":"","ackUser":"","portalUrl":"https://lmryanmatuszewski.logicmonitor.com/santaba/uiv4/alert#detail~id=${TEST_ID}","eventSource":""}
EOF
)

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
  echo "FAIL: Event Hub returned HTTP ${HTTP_CODE}" >&2
  exit 1
fi

echo "Demo alert fired: ${TEST_ID}"
echo "Expect an incident in Sentinel within ~5-10 minutes."
echo "Watch: portal.azure.com -> Sentinel -> law-lmsent-poc -> Incidents (filter: New)"
