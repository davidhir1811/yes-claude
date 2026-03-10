#!/usr/bin/env bash
# Yes Claude... Claude Code Adapter
# Parses Claude Code's hook stdin and formats responses.
# Sourced by hooks/hook.sh — do not run directly.

YC_SOURCE="claude"

YC_CHOICES_JSON='[{"stringValue":"Allow"},{"stringValue":"Deny"},{"stringValue":"Allow Always"}]'

yc_parse_input() {
  local input="$1"

  eval "$(echo "$input" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    tool = data.get('tool', 'Unknown')
    inp = data.get('input', '')
    if isinstance(inp, dict):
        inp = json.dumps(inp, separators=(',', ':'))
    print(f'YC_COMMAND={tool}: {inp}')
except:
    print('YC_COMMAND=Unknown command')
")"
}

yc_format_response() {
  local response="$1"
  case "$response" in
    "Allow") echo '{"allow": true}' ;;
    "Allow Always") echo '{"allow": true, "always": true}' ;;
    *) echo '{"allow": false}' ;;
  esac
}

yc_default_response() {
  echo '{"allow": false}'
}
