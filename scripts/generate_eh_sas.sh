#!/usr/bin/env bash
# Description: Generate a Send-only SAS token for the Event Hub that LM will use in its HTTP Delivery integration.
# Description: Prints the token plus the full Authorization header value ready to paste into the LM integration config.

set -euo pipefail

RG="${RG:-CTA_LM_Sentinel_POC}"
NAMESPACE="${NAMESPACE:-}"
HUB="${HUB:-lm-alerts}"
POLICY="${POLICY:-lm-send}"
EXPIRY_DAYS="${EXPIRY_DAYS:-730}"

if [[ -z "${NAMESPACE}" ]]; then
  NAMESPACE=$(az eventhubs namespace list -g "${RG}" --query "[?starts_with(name, 'ehns-lmsent-poc')] | [0].name" -o tsv)
  if [[ -z "${NAMESPACE}" ]]; then
    echo "ERROR: Could not discover EH namespace in RG ${RG}. Set NAMESPACE=..." >&2
    exit 1
  fi
fi

echo "[sas] Namespace: ${NAMESPACE}"
echo "[sas] Hub:       ${HUB}"
echo "[sas] Policy:    ${POLICY}"

KEY=$(az eventhubs eventhub authorization-rule keys list \
  --resource-group "${RG}" \
  --namespace-name "${NAMESPACE}" \
  --eventhub-name "${HUB}" \
  --name "${POLICY}" \
  --query primaryKey -o tsv)

if [[ -z "${KEY}" ]]; then
  echo "ERROR: Failed to retrieve primary key for ${POLICY}" >&2
  exit 1
fi

RESOURCE_URI="https://${NAMESPACE}.servicebus.windows.net/${HUB}"
ENCODED_URI=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${RESOURCE_URI}")
EXPIRY_EPOCH=$(( $(date +%s) + EXPIRY_DAYS * 86400 ))

STRING_TO_SIGN=$(printf '%s\n%s' "${ENCODED_URI}" "${EXPIRY_EPOCH}")
SIGNATURE=$(printf '%s' "${STRING_TO_SIGN}" | openssl dgst -sha256 -hmac "${KEY}" -binary | base64)
ENCODED_SIG=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${SIGNATURE}")

SAS_TOKEN="SharedAccessSignature sr=${ENCODED_URI}&sig=${ENCODED_SIG}&se=${EXPIRY_EPOCH}&skn=${POLICY}"

echo ""
echo "[sas] Token generated. Expires: $(date -d "@${EXPIRY_EPOCH}" 2>/dev/null || date -r "${EXPIRY_EPOCH}")"
echo ""
echo "==== LM HTTP Delivery integration ===="
echo "URL:"
echo "  https://${NAMESPACE}.servicebus.windows.net/${HUB}/messages"
echo ""
echo "Method: POST"
echo ""
echo "Headers:"
echo "  Authorization: ${SAS_TOKEN}"
echo "  Content-Type: application/json"
echo ""
echo "======================================"
