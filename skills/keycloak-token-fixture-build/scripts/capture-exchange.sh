#!/usr/bin/env bash
set -euo pipefail

# Two-leg capture for standard token-exchange fixtures (KC 26.5.5).
# Split into subcommands because the fixture's commitment point
# (prediction-target.md) sits BETWEEN the legs — see
# references/token-exchange.md.
#
#   capture-exchange.sh subject         # leg 1: mint the subject token
#   capture-exchange.sh exchange <lbl>  # leg 2: exchange it (run twice,
#                                       # e.g. labels 'a' and 'b', for the
#                                       # determinism check)
#
# Env (leg 1): REALM, SUBJECT_CLIENT_ID, SUBJECT_CLIENT_SECRET,
#              USERNAME, PASSWORD, [SUBJECT_SCOPE]
# Env (leg 2): REALM, EXCHANGE_CLIENT_ID, EXCHANGE_CLIENT_SECRET,
#              [AUDIENCE], [EXCHANGE_SCOPE], [REQUESTED_TOKEN_TYPE]
# Both:        [CONTAINER=keycloak], [OUT_DIR=.]
#
# Outputs (into OUT_DIR, which should be the fixture directory):
#   subject:  request-1.json subject-token.json subject-token.jwt log-1.txt
#   exchange: request-2.json response-2-<lbl>.json actual-token-2-<lbl>.json
#             log-2-<lbl>.txt

CONTAINER="${CONTAINER:-keycloak}"
OUT_DIR="${OUT_DIR:-.}"
BASE_URL="${BASE_URL:-http://localhost:8080}"
TOKEN_URL="${BASE_URL}/realms/${REALM:?REALM is required}/protocol/openid-connect/token"

decode_payload() {
  local jwt="$1"
  local payload
  payload=$(echo "${jwt}" | cut -d. -f2)
  local pad=$(( 4 - ${#payload} % 4 ))
  [[ $pad -ne 4 ]] && payload="${payload}$(printf '=%.0s' $(seq 1 $pad))"
  echo "${payload}" | tr '_-' '/+' | base64 -d 2>/dev/null | jq .
}

# Bracket a curl with RFC3339 timestamps and slice the container log,
# same pattern as the target skill's capture-tokens.sh (post-hoc
# --since/--until; a backgrounded `docker logs -f` leaks across captures).
post_bracketed() {
  local logfile="$1"; shift
  local start_ts end_ts response
  start_ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")
  response=$(curl -s -X POST "${TOKEN_URL}" \
    -H "Content-Type: application/x-www-form-urlencoded" "$@")
  sleep 0.5
  end_ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")
  docker logs --since "${start_ts}" --until "${end_ts}" "${CONTAINER}" \
    > "${logfile}" 2>&1
  echo "${response}"
}

write_request_json() {
  # write_request_json <outfile> key=value...
  local outfile="$1"; shift
  local form_json curl_str="curl -X POST ${TOKEN_URL} -H 'Content-Type: application/x-www-form-urlencoded'"
  form_json=$(jq -n '{}')
  for kv in "$@"; do
    local k="${kv%%=*}" v="${kv#*=}"
    form_json=$(echo "${form_json}" | jq --arg k "$k" --arg v "$v" '. + {($k): $v}')
    curl_str="${curl_str} -d '${k}=${v}'"
  done
  jq -n --arg url "${TOKEN_URL}" --argjson form "${form_json}" --arg curl "${curl_str}" \
    '{method:"POST", url:$url, headers:{"Content-Type":"application/x-www-form-urlencoded"}, form:$form, curl:$curl}' \
    > "${outfile}"
}

cmd="${1:?subcommand required: subject | exchange}"

case "${cmd}" in
  subject)
    : "${SUBJECT_CLIENT_ID:?}" "${SUBJECT_CLIENT_SECRET:?}" "${USERNAME:?}" "${PASSWORD:?}"
    args=(
      "grant_type=password"
      "client_id=${SUBJECT_CLIENT_ID}"
      "client_secret=${SUBJECT_CLIENT_SECRET}"
      "username=${USERNAME}"
      "password=${PASSWORD}"
    )
    [[ -n "${SUBJECT_SCOPE:-}" ]] && args+=("scope=${SUBJECT_SCOPE}")

    echo "=== Leg 1: minting subject token (client=${SUBJECT_CLIENT_ID}, user=${USERNAME}) ==="
    curl_args=(); for kv in "${args[@]}"; do curl_args+=(-d "${kv}"); done
    response=$(post_bracketed "${OUT_DIR}/log-1.txt" "${curl_args[@]}")

    token=$(echo "${response}" | jq -r '.access_token // empty')
    if [[ -z "${token}" ]]; then
      echo "${response}" | jq . >&2
      echo "✗ Leg 1 failed — no access_token in response" >&2
      exit 1
    fi
    write_request_json "${OUT_DIR}/request-1.json" "${args[@]}"
    printf '%s' "${token}" > "${OUT_DIR}/subject-token.jwt"
    decode_payload "${token}" > "${OUT_DIR}/subject-token.json"
    echo "✓ subject-token.jwt / subject-token.json / request-1.json / log-1.txt"
    echo "  Subject token exp: $(jq -r '.exp' "${OUT_DIR}/subject-token.json") (iat $(jq -r '.iat' "${OUT_DIR}/subject-token.json"))"
    echo "  Now write prediction-target.md BEFORE running the exchange leg."
    ;;

  exchange)
    label="${2:?label required (e.g. 'a' or 'b' for the determinism pair)}"
    : "${EXCHANGE_CLIENT_ID:?}" "${EXCHANGE_CLIENT_SECRET:?}"
    subject_jwt_file="${OUT_DIR}/subject-token.jwt"
    [[ -f "${subject_jwt_file}" ]] || { echo "✗ ${subject_jwt_file} missing — run 'subject' first" >&2; exit 1; }
    subject_token=$(cat "${subject_jwt_file}")

    args=(
      "grant_type=urn:ietf:params:oauth:grant-type:token-exchange"
      "client_id=${EXCHANGE_CLIENT_ID}"
      "client_secret=${EXCHANGE_CLIENT_SECRET}"
      "subject_token=${subject_token}"
      "subject_token_type=urn:ietf:params:oauth:token-type:access_token"
    )
    [[ -n "${AUDIENCE:-}" ]] && args+=("audience=${AUDIENCE}")
    [[ -n "${EXCHANGE_SCOPE:-}" ]] && args+=("scope=${EXCHANGE_SCOPE}")
    [[ -n "${REQUESTED_TOKEN_TYPE:-}" ]] && args+=("requested_token_type=${REQUESTED_TOKEN_TYPE}")

    echo "=== Leg 2 (${label}): exchanging (client=${EXCHANGE_CLIENT_ID}, audience='${AUDIENCE:-}') ==="
    curl_args=(); for kv in "${args[@]}"; do curl_args+=(-d "${kv}"); done
    response=$(post_bracketed "${OUT_DIR}/log-2-${label}.txt" "${curl_args[@]}")
    echo "${response}" | jq . > "${OUT_DIR}/response-2-${label}.json"

    token=$(echo "${response}" | jq -r '.access_token // empty')
    if [[ -z "${token}" ]]; then
      echo "${response}" | jq . >&2
      echo "✗ Leg 2 failed — see response-2-${label}.json" >&2
      exit 1
    fi
    # request-2.json is identical across determinism mints (same subject
    # token, same params) — write once.
    [[ -f "${OUT_DIR}/request-2.json" ]] || write_request_json "${OUT_DIR}/request-2.json" "${args[@]}"
    decode_payload "${token}" > "${OUT_DIR}/actual-token-2-${label}.json"
    echo "✓ actual-token-2-${label}.json / response-2-${label}.json / log-2-${label}.txt"
    echo "  jti: $(jq -r '.jti' "${OUT_DIR}/actual-token-2-${label}.json")"
    echo "  issued_token_type: $(echo "${response}" | jq -r '.issued_token_type // "absent"')"
    ;;

  *)
    echo "unknown subcommand '${cmd}' — use: subject | exchange <label>" >&2
    exit 1
    ;;
esac
