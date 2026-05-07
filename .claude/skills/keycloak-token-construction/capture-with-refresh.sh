#!/usr/bin/env bash
# Positive-control capture: re-issues a client_credentials token after
# temporarily setting `client_credentials.use_refresh_token=true` on
# test-client, so the resulting fixture exercises the *non*-transient branch
# where AccessTokenResponseBuilder keeps `sid` on the token.
#
# Companion to capture-tokens.sh, which exercises the default (transient,
# no-refresh-token) branch where `OAuth2GrantTypeBase.java:128-135` nulls
# `sid` post-`transformAccessToken`.
#
# The attribute is restored to its prior value on exit, so re-running
# capture-tokens.sh afterwards still produces the original sid-less fixtures.

set -euo pipefail

REALM=myrealm
CLIENT_ID=test-client
CLIENT_SECRET=test-secret
TOKEN_URL="http://localhost:8080/realms/${REALM}/protocol/openid-connect/token"
ADMIN_URL="http://localhost:8080/admin/realms/${REALM}"
CONTAINER=keycloak
LABEL="with-refresh-openid"
ATTR="client_credentials.use_refresh_token"

mkdir -p fixtures

ADMIN_TOKEN=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=admin" | jq -r '.access_token')
[[ -z "${ADMIN_TOKEN}" || "${ADMIN_TOKEN}" == "null" ]] && { echo "FAIL: admin token"; exit 1; }

CLIENT_UUID=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "${ADMIN_URL}/clients?clientId=${CLIENT_ID}" | jq -r '.[0].id')
[[ -z "${CLIENT_UUID}" || "${CLIENT_UUID}" == "null" ]] && { echo "FAIL: client uuid for ${CLIENT_ID}"; exit 1; }

PRIOR=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  "${ADMIN_URL}/clients/${CLIENT_UUID}" | jq -r ".attributes.\"${ATTR}\" // \"\"")

restore() {
  curl -s -X PUT -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    "${ADMIN_URL}/clients/${CLIENT_UUID}" \
    -d "{\"attributes\":{\"${ATTR}\":\"${PRIOR}\"}}" >/dev/null
  echo "Restored ${ATTR} on ${CLIENT_ID} to '${PRIOR}'"
}
trap restore EXIT

echo "Setting ${ATTR}=true on ${CLIENT_ID} (was '${PRIOR}')"
curl -s -X PUT -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  "${ADMIN_URL}/clients/${CLIENT_UUID}" \
  -d "{\"attributes\":{\"${ATTR}\":\"true\"}}" >/dev/null

start_ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")
RESP=$(curl -s -X POST "${TOKEN_URL}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=openid")
sleep 0.5
end_ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")

echo "${RESP}" | jq . > "fixtures/response-${LABEL}.json"
docker logs --since "${start_ts}" --until "${end_ts}" "${CONTAINER}" \
  > "fixtures/logs-${LABEL}.log" 2>&1

AT=$(echo "${RESP}" | jq -r '.access_token // empty')
[[ -z "${AT}" ]] && { echo "FAIL: no access_token in response — see fixtures/response-${LABEL}.json"; exit 1; }

PAYLOAD=$(echo "${AT}" | cut -d. -f2)
PAD=$(( 4 - ${#PAYLOAD} % 4 ))
[[ $PAD -ne 4 ]] && PAYLOAD="${PAYLOAD}$(printf '=%.0s' $(seq 1 $PAD))"
echo "${PAYLOAD}" | tr '_-' '/+' | base64 -d 2>/dev/null | jq . > "fixtures/token-${LABEL}.json"

echo "  ✓ response-${LABEL}.json, logs-${LABEL}.log, token-${LABEL}.json"

if jq -e 'has("sid")' "fixtures/token-${LABEL}.json" >/dev/null && \
   jq -e '.refresh_token != null' "fixtures/response-${LABEL}.json" >/dev/null; then
  echo "  ✓ sid present on access token; refresh_token present on response — non-transient branch confirmed."
else
  echo "  ✗ expected sid+refresh_token; got:"
  jq '{sid, jti}' "fixtures/token-${LABEL}.json"
  jq 'keys' "fixtures/response-${LABEL}.json"
  exit 1
fi
