#!/usr/bin/env bash
# Yes Claude... Admin CLI
# Requires: gcloud auth application-default login
#
# Usage:
#   ./scripts/admin.sh get-limits
#   ./scripts/admin.sh set-limits --anonymous 5 --free 20 --premium 1000
#   ./scripts/admin.sh user-info <uid>
#   ./scripts/admin.sh set-tier <uid> <tier>
#   ./scripts/admin.sh reset-counter <uid>

set -e

FIREBASE_PROJECT="yes-claude-XXXXX"
FIRESTORE_BASE="https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT}/databases/(default)/documents"

get_token() {
  local token
  token=$(gcloud auth application-default print-access-token 2>/dev/null) || {
    echo "Error: Not authenticated. Run: gcloud auth application-default login" >&2
    exit 1
  }
  echo "$token"
}

cmd_get_limits() {
  local token
  token=$(get_token)
  echo "Current tier limits:"
  echo "---"
  curl -sf -H "Authorization: Bearer $token" \
    "${FIRESTORE_BASE}/config/tiers" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
fields = doc.get('fields', {})
for tier, val in sorted(fields.items()):
    mv = val.get('mapValue', {}).get('fields', {})
    parts = []
    for k, v in sorted(mv.items()):
        num = v.get('integerValue', v.get('stringValue', '?'))
        parts.append(f'{k}={num}')
    print(f'  {tier}: {\"  \".join(parts)}')
"
}

cmd_set_limits() {
  local token anonymous="" free="" premium=""
  token=$(get_token)

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --anonymous) anonymous="$2"; shift 2 ;;
      --free) free="$2"; shift 2 ;;
      --premium) premium="$2"; shift 2 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done

  local fields=""

  if [ -n "$anonymous" ]; then
    fields="${fields}\"anonymous\":{\"mapValue\":{\"fields\":{\"dailyLimit\":{\"integerValue\":\"${anonymous}\"}}}},"
  fi
  if [ -n "$free" ]; then
    fields="${fields}\"free\":{\"mapValue\":{\"fields\":{\"dailyLimit\":{\"integerValue\":\"${free}\"}}}},"
  fi
  if [ -n "$premium" ]; then
    fields="${fields}\"premium\":{\"mapValue\":{\"fields\":{\"monthlyLimit\":{\"integerValue\":\"${premium}\"}}}},"
  fi

  fields="${fields%,}"

  if [ -z "$fields" ]; then
    echo "Specify at least one: --anonymous N --free N --premium N" >&2
    exit 1
  fi

  local mask_params=""
  [ -n "$anonymous" ] && mask_params="${mask_params}&updateMask.fieldPaths=anonymous"
  [ -n "$free" ] && mask_params="${mask_params}&updateMask.fieldPaths=free"
  [ -n "$premium" ] && mask_params="${mask_params}&updateMask.fieldPaths=premium"
  mask_params="${mask_params#&}"

  curl -sf -X PATCH \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "${FIRESTORE_BASE}/config/tiers?${mask_params}" \
    -d "{\"fields\":{${fields}}}" | python3 -m json.tool

  echo "Limits updated."
}

cmd_user_info() {
  local uid="$1" token
  if [ -z "$uid" ]; then
    echo "Usage: admin.sh user-info <uid>" >&2
    exit 1
  fi
  token=$(get_token)

  echo "User: $uid"
  echo "---"
  curl -sf -H "Authorization: Bearer $token" \
    "${FIRESTORE_BASE}/users/${uid}" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
fields = doc.get('fields', {})
for k, v in sorted(fields.items()):
    if 'stringValue' in v:
        print(f'  {k}: {v[\"stringValue\"]}')
    elif 'integerValue' in v:
        print(f'  {k}: {v[\"integerValue\"]}')
    elif 'timestampValue' in v:
        print(f'  {k}: {v[\"timestampValue\"]}')
    elif 'arrayValue' in v:
        vals = [x.get('stringValue', str(x)) for x in v['arrayValue'].get('values', [])]
        print(f'  {k}: [{\", \".join(vals)}]')
    else:
        print(f'  {k}: {json.dumps(v)}')
"
}

cmd_set_tier() {
  local uid="$1" tier="$2" token
  if [ -z "$uid" ] || [ -z "$tier" ]; then
    echo "Usage: admin.sh set-tier <uid> <tier>" >&2
    exit 1
  fi
  token=$(get_token)

  curl -sf -X PATCH \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "${FIRESTORE_BASE}/users/${uid}?updateMask.fieldPaths=tier" \
    -d "{\"fields\":{\"tier\":{\"stringValue\":\"${tier}\"}}}" > /dev/null

  echo "Set tier for $uid to $tier"
}

cmd_reset_counter() {
  local uid="$1" token
  if [ -z "$uid" ]; then
    echo "Usage: admin.sh reset-counter <uid>" >&2
    exit 1
  fi
  token=$(get_token)

  curl -sf -X PATCH \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "${FIRESTORE_BASE}/users/${uid}?updateMask.fieldPaths=dailyCount&updateMask.fieldPaths=monthlyCount" \
    -d "{\"fields\":{\"dailyCount\":{\"integerValue\":\"0\"},\"monthlyCount\":{\"integerValue\":\"0\"}}}" > /dev/null

  echo "Reset counters for $uid"
}

case "${1:-help}" in
  get-limits)    cmd_get_limits ;;
  set-limits)    shift; cmd_set_limits "$@" ;;
  user-info)     cmd_user_info "$2" ;;
  set-tier)      cmd_set_tier "$2" "$3" ;;
  reset-counter) cmd_reset_counter "$2" ;;
  *)
    echo "Yes Claude... Admin CLI"
    echo ""
    echo "Usage:"
    echo "  admin.sh get-limits                                    View current tier limits"
    echo "  admin.sh set-limits --anonymous 5 --free 20 --premium 1000  Update limits"
    echo "  admin.sh user-info <uid>                               View user details"
    echo "  admin.sh set-tier <uid> <tier>                         Set user tier"
    echo "  admin.sh reset-counter <uid>                           Reset usage counters"
    echo ""
    echo "Requires: gcloud auth application-default login"
    ;;
esac
