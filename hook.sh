#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="$HOME/.yes-claude/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo '{"allow": false}'
  exit 0
fi

DEVICE_ID=$(grep -o '"deviceId":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
SECRET_TOKEN=$(grep -o '"secretToken":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
FIREBASE_PROJECT=$(grep -o '"firebaseProject":"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
FIRESTORE_BASE="https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT}/databases/(default)/documents"

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | grep -o '"tool"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || echo "Unknown")
TOOL_INPUT=$(echo "$INPUT" | grep -o '"input"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
DISPLAY_COMMAND="${COMMAND}: ${TOOL_INPUT}"

REQUEST_ID=$(head -c 8 /dev/urandom | xxd -p)

# Cross-platform date: try GNU date first, fall back to BSD
EXPIRES_AT=$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)

# Escape the command for JSON
ESCAPED_COMMAND=$(echo "$DISPLAY_COMMAND" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g')

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
