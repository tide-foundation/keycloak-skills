#!/usr/bin/env bash
set -euo pipefail

REALM=myrealm
TOKEN_URL="http://localhost:8080/realms/${REALM}/protocol/openid-connect/token"
CONTAINER=keycloak

mkdir -p fixtures

# Captures one request and the exact slice of container logs it produced.
# We bracket the curl with RFC3339 timestamps and pull logs post-hoc with
# `docker logs --since --until`, instead of running a live `docker logs -f`
# tail in the background. The old approach leaked logs across captures
# because `kill ${LOG_PID}` doesn't reliably stop `docker logs -f` before
# the next capture starts streaming.
capture() {
  local label="$1"
  local client_id="$2"
  local client_secret="$3"
  local scope="${4:-}"

  echo "=== Capturing: ${label} (client=${client_id}, scope='${scope}') ==="

  local start_ts
  start_ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")

  local data="grant_type=client_credentials&client_id=${client_id}&client_secret=${client_secret}"
  if [[ -n "${scope}" ]]; then
    data="${data}&scope=${scope}"
  fi

  local response
  response=$(curl -s -X POST "${TOKEN_URL}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "${data}")

  echo "${response}" | jq . > "fixtures/response-${label}.json"

  # Settle so the request's log lines are flushed to docker's buffer
  sleep 0.5
  local end_ts
  end_ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")

  docker logs --since "${start_ts}" --until "${end_ts}" "${CONTAINER}" \
    > "fixtures/logs-${label}.log" 2>&1

  local token
  token=$(echo "${response}" | jq -r '.access_token // empty')

  if [[ -z "${token}" ]]; then
    echo "  ⚠ No access_token returned — see fixtures/response-${label}.json"
    return
  fi

  local payload
  payload=$(echo "${token}" | cut -d. -f2)
  local pad=$(( 4 - ${#payload} % 4 ))
  [[ $pad -ne 4 ]] && payload="${payload}$(printf '=%.0s' $(seq 1 $pad))"
  echo "${payload}" | tr '_-' '/+' | base64 -d 2>/dev/null | jq . > "fixtures/token-${label}.json"

  echo "  ✓ token-${label}.json, response-${label}.json, logs-${label}.log"
}

# Full-scope client (fullScopeAllowed=true) — exercises the full-scope
# branch in TokenManager.getAccess (returns the user's expanded role
# mappings directly, TokenManager.java:606-609).
capture "default-scopes"          test-client  test-secret  ""
capture "openid"                  test-client  test-secret  "openid"
capture "openid-offline-access"   test-client  test-secret  "openid offline_access"
capture "custom-scope"            test-client  test-secret  "custom-scope"

# Restricted-scope client (fullScopeAllowed=false) — exercises the
# role-intersection branch in TokenManager.getAccess (intersects expanded
# scope-mapping roles with expanded user roles, TokenManager.java:610-635).
capture "restricted-default-scopes"        test-client-restricted  test-secret-restricted  ""
capture "restricted-openid"                test-client-restricted  test-secret-restricted  "openid"
capture "restricted-openid-offline-access" test-client-restricted  test-secret-restricted  "openid offline_access"

echo
echo "Done. Fixtures in ./fixtures/"
ls -1 fixtures/
