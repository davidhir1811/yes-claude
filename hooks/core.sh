#!/usr/bin/env bash
# Yes Claude... Core Hook Library
# Shared Firestore API, polling, and config loading.
# Sourced by hooks/hook.sh — do not run directly.

yc_load_config() {
  local config_file="$HOME/.yes-claude/config.json"
  if [ ! -f "$config_file" ]; then
    return 1
  fi

  eval "$(CONFIG_FILE="$config_file" python3 -c "
import json, os
c = json.load(open(os.environ['CONFIG_FILE']))
print(f'YC_DEVICE_ID={c[\"deviceId\"]}')
print(f'YC_SECRET_TOKEN={c[\"secretToken\"]}')
print(f'YC_FIREBASE_PROJECT={c[\"firebaseProject\"]}')
")"

  if [ -z "$YC_DEVICE_ID" ] || [ -z "$YC_SECRET_TOKEN" ] || [ -z "$YC_FIREBASE_PROJECT" ]; then
    return 1
  fi

  YC_FIRESTORE_BASE="https://firestore.googleapis.com/v1/projects/${YC_FIREBASE_PROJECT}/databases/(default)/documents"
  return 0
}

yc_create_request() {
  local request_id="$1"
  local command="$2"
  local choices_json="$3"
  local source="$4"
  local session_label="${5:-$(basename "$PWD")}"
  local machine_id="${6:-$(hostname)}"

  local expires_at
  expires_at=$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)

  local escaped_command
  escaped_command=$(echo "$command" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip())[1:-1])")

  curl -s -X POST \
    "${YC_FIRESTORE_BASE}/requests?documentId=${request_id}" \
    -H "Content-Type: application/json" \
    -d "{
      \"fields\": {
        \"deviceId\": {\"stringValue\": \"${YC_DEVICE_ID}\"},
        \"secretToken\": {\"stringValue\": \"${YC_SECRET_TOKEN}\"},
        \"command\": {\"stringValue\": \"${escaped_command}\"},
        \"choices\": {\"arrayValue\": {\"values\": ${choices_json}}},
        \"status\": {\"stringValue\": \"pending\"},
        \"response\": {\"nullValue\": null},
        \"sessionLabel\": {\"stringValue\": \"${session_label}\"},
        \"machineId\": {\"stringValue\": \"${machine_id}\"},
        \"source\": {\"stringValue\": \"${source}\"},
        \"createdAt\": {\"timestampValue\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"},
        \"expiresAt\": {\"timestampValue\": \"${expires_at}\"}
      }
    }" > /dev/null
}

yc_poll_response() {
  local request_id="$1"
  local timeout="${2:-300}"
  local elapsed=0

  while [ $elapsed -lt "$timeout" ]; do
    local response_doc
    response_doc=$(curl -s "${YC_FIRESTORE_BASE}/requests/${request_id}")
    local status
    status=$(echo "$response_doc" | grep -o '"status"[^}]*' | grep -o '"stringValue":"[^"]*"' | cut -d'"' -f4)

    if [ "$status" = "responded" ] || [ "$status" = "expired" ]; then
      YC_RESPONSE=$(echo "$response_doc" | grep -o '"response"[^}]*' | grep -o '"stringValue":"[^"]*"' | cut -d'"' -f4)
      return 0
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  YC_RESPONSE=""
  return 1
}

yc_generate_id() {
  od -An -tx1 -N8 /dev/urandom | tr -d ' \n'
}
