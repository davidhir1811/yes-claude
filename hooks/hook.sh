#!/usr/bin/env bash
set -euo pipefail

# Yes Claude... Hook Entry Point
# Sources core library + CLI adapter, then runs the permission flow.
#
# The adapter is determined by the YC_CLI env var (default: claude).
# To support a new CLI, create hooks/adapters/<cli>.sh with:
#   yc_parse_input()      - parse stdin into YC_COMMAND
#   yc_format_response()  - map response string to CLI output
#   yc_default_response() - default deny output
#   YC_SOURCE             - source identifier
#   YC_CHOICES_JSON       - Firestore array JSON for choices

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="${YC_CLI:-claude}"

# Source core library
source "$SCRIPT_DIR/core.sh"

# Source CLI adapter
ADAPTER="$SCRIPT_DIR/adapters/${CLI}.sh"
if [ ! -f "$ADAPTER" ]; then
  echo '{"allow": false}'
  exit 0
fi
source "$ADAPTER"

# Load config
if ! yc_load_config; then
  yc_default_response
  exit 0
fi

# Read and parse stdin
INPUT=$(cat)
yc_parse_input "$INPUT"

# Create request
REQUEST_ID=$(yc_generate_id)
yc_create_request "$REQUEST_ID" "$YC_COMMAND" "$YC_CHOICES_JSON" "$YC_SOURCE"

# Poll for response
if yc_poll_response "$REQUEST_ID"; then
  yc_format_response "$YC_RESPONSE"
else
  yc_default_response
fi
