#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="$HOME/.yes-claude/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo '{"allow": false}'
  exit 0
fi

eval "$(CONFIG_FILE="$CONFIG_FILE" python3 -c "
import json, os
c = json.load(open(os.environ['CONFIG_FILE']))
print(f'DEVICE_ID={c[\"deviceId\"]}')
print(f'SECRET_TOKEN={c[\"secretToken\"]}')
print(f'FIREBASE_PROJECT={c[\"firebaseProject\"]}')
")"

if [ -z "$DEVICE_ID" ] || [ -z "$SECRET_TOKEN" ] || [ -z "$FIREBASE_PROJECT" ]; then
  echo '{"allow": false}'
  exit 0
fi

FIRESTORE_BASE="https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT}/databases/(default)/documents"

INPUT=$(cat)

eval "$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    tool = data.get('tool', 'Unknown')
    inp = data.get('input', '')
    if isinstance(inp, dict):
        inp = json.dumps(inp, separators=(',', ':'))
    print(f'COMMAND={tool}')
    print(f'TOOL_INPUT={inp}')
except:
    print('COMMAND=Unknown')
    print('TOOL_INPUT=')
")"
DISPLAY_COMMAND="${COMMAND}: ${TOOL_INPUT}"

REQUEST_ID=$(od -An -tx1 -N8 /dev/urandom | tr -d ' \n')

# Cross-platform date: try GNU date first, fall back to BSD
EXPIRES_AT=$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)

# Escape the command for JSON
ESCAPED_COMMAND=$(echo "$DISPLAY_COMMAND" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip())[1:-1])")

curl -s -X POST \
  "${FIRESTORE_BASE}/requests?documentId=${REQUEST_ID}" \
  -H "Content-Type: application/json" \
  -d "{
    \"fields\": {
      \"deviceId\": {\"stringValue\": \"${DEVICE_ID}\"},
      \"secretToken\": {\"stringValue\": \"${SECRET_TOKEN}\"},
      \"command\": {\"stringValue\": \"${ESCAPED_COMMAND}\"},
      \"choices\": {\"arrayValue\": {\"values\": [
        {\"stringValue\": \"Allow\"},
        {\"stringValue\": \"Deny\"},
        {\"stringValue\": \"Allow Always\"}
      ]}},
      \"status\": {\"stringValue\": \"pending\"},
      \"response\": {\"nullValue\": null},
      \"createdAt\": {\"timestampValue\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"},
      \"expiresAt\": {\"timestampValue\": \"${EXPIRES_AT}\"}
    }
  }" > /dev/null

TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  RESPONSE_DOC=$(curl -s "${FIRESTORE_BASE}/requests/${REQUEST_ID}")
  STATUS=$(echo "$RESPONSE_DOC" | grep -o '"status"[^}]*' | grep -o '"stringValue":"[^"]*"' | cut -d'"' -f4)

  if [ "$STATUS" = "responded" ] || [ "$STATUS" = "expired" ]; then
    RESPONSE=$(echo "$RESPONSE_DOC" | grep -o '"response"[^}]*' | grep -o '"stringValue":"[^"]*"' | cut -d'"' -f4)
    case "$RESPONSE" in
      "Allow") echo '{"allow": true}'; exit 0 ;;
      "Allow Always") echo '{"allow": true, "always": true}'; exit 0 ;;
      *) echo '{"allow": false}'; exit 0 ;;
    esac
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

echo '{"allow": false}'
exit 0
