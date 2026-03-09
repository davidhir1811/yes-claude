#!/usr/bin/env bash
set -euo pipefail

# Yes Claude... Installer for Mac/Linux
# Usage: curl -sSL https://raw.githubusercontent.com/davidhir1811/yes-claude/main/install.sh | bash

INSTALL_DIR="$HOME/.yes-claude"
HOOK_URL="https://raw.githubusercontent.com/davidhir1811/yes-claude/main/hook.sh"
FIREBASE_PROJECT="yes-claude-XXXXX"
FIRESTORE_BASE="https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT}/databases/(default)/documents"

echo "==================================="
echo "  Yes Claude... Installer"
echo "==================================="
echo ""

mkdir -p "$INSTALL_DIR"

echo "Downloading hook script..."
curl -sSL "$HOOK_URL" -o "$INSTALL_DIR/hook.sh"
chmod +x "$INSTALL_DIR/hook.sh"

# Generate 6-character pairing code
PAIRING_CODE=$(od -An -tx1 -N3 /dev/urandom | tr -d ' \n' | tr 'a-f' 'A-F' | head -c 6)

# Generate shared secret token
SECRET_TOKEN=$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')

echo "Registering device..."
CREATE_RESPONSE=$(curl -s -X POST \
  "${FIRESTORE_BASE}/devices?documentId=${PAIRING_CODE}" \
  -H "Content-Type: application/json" \
  -d "{
    \"fields\": {
      \"secretToken\": {\"stringValue\": \"${SECRET_TOKEN}\"},
      \"fcmToken\": {\"stringValue\": \"\"},
      \"createdAt\": {\"timestampValue\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"},
      \"pairedAt\": {\"nullValue\": null}
    }
  }")

if echo "$CREATE_RESPONSE" | grep -q "error"; then
  echo "ERROR: Failed to register device."
  echo "$CREATE_RESPONSE"
  exit 1
fi

echo ""
echo "==================================="
echo "  Enter this code in the app:"
echo ""
echo "        ${PAIRING_CODE}"
echo ""
echo "==================================="
echo ""
echo "Waiting for pairing..."

TIMEOUT=600
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  DEVICE_DOC=$(curl -s "${FIRESTORE_BASE}/devices/${PAIRING_CODE}")
  FCM_TOKEN=$(echo "$DEVICE_DOC" | grep -o '"fcmToken"[^}]*' | grep -o '"stringValue":"[^"]*"' | cut -d'"' -f4)

  if [ -n "$FCM_TOKEN" ] && [ "$FCM_TOKEN" != "" ]; then
    echo "Paired successfully!"
    break
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo "ERROR: Pairing timed out after 10 minutes."
  exit 1
fi

cat > "$INSTALL_DIR/config.json" << EOF
{
  "deviceId": "${PAIRING_CODE}",
  "secretToken": "${SECRET_TOKEN}",
  "firebaseProject": "${FIREBASE_PROJECT}"
}
EOF
chmod 600 "$INSTALL_DIR/config.json"

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

if [ -f "$CLAUDE_SETTINGS" ]; then
  if command -v python3 &> /dev/null; then
    CLAUDE_SETTINGS="$CLAUDE_SETTINGS" INSTALL_DIR="$INSTALL_DIR" python3 -c "
import json, os
settings_path = os.environ['CLAUDE_SETTINGS']
install_dir = os.environ['INSTALL_DIR']
with open(settings_path, 'r') as f:
    settings = json.load(f)
hook = {'type': 'command', 'command': install_dir + '/hook.sh'}
if 'hooks' not in settings:
    settings['hooks'] = {}
if 'permissionPrompt' not in settings['hooks']:
    settings['hooks']['permissionPrompt'] = []
existing = [h for h in settings['hooks']['permissionPrompt'] if h.get('command') == install_dir + '/hook.sh']
if not existing:
    settings['hooks']['permissionPrompt'].append(hook)
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
"
  else
    echo "WARNING: python3 not found. Please manually add the hook to $CLAUDE_SETTINGS"
  fi
else
  cat > "$CLAUDE_SETTINGS" << SETTINGS
{
  "hooks": {
    "permissionPrompt": [
      {
        "type": "command",
        "command": "$INSTALL_DIR/hook.sh"
      }
    ]
  }
}
SETTINGS
fi

echo ""
echo "Installation complete!"
echo "Config: $INSTALL_DIR/config.json"
echo "Hook: $INSTALL_DIR/hook.sh"
