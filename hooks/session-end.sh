#!/bin/bash
# Layer 4: Fires on Claude Code session end
# Stores session summary in Hindsight

HINDSIGHT_URL="${HINDSIGHT_URL:-http://localhost:8888}"

BRANCH=""
LAST_COMMIT=""
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null)
  LAST_COMMIT=$(git log -1 --pretty='%s' 2>/dev/null)
fi

CONTENT="Session ended $(date). Branch: ${BRANCH:-none}. Last commit: ${LAST_COMMIT:-none}."

# Use python for safe JSON encoding
JSON_BODY=$(python3 -c "
import json, sys
print(json.dumps({'items': [{'content': sys.argv[1]}]}))
" "$CONTENT" 2>/dev/null)

if [ -n "$JSON_BODY" ]; then
  curl -sf -X POST "$HINDSIGHT_URL/v1/default/banks/claude-sessions/memories" \
    -H 'Content-Type: application/json' \
    -d "$JSON_BODY" \
    2>/dev/null
fi

exit 0
