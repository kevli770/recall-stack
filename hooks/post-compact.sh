#!/bin/bash
# Fires after context compaction -- re-injects critical layers
# Layers 1-2 (CLAUDE.md, primer.md) survive compaction (system prompt)
# Layers 3-4 (git context, Hindsight) live in conversation and get compacted
# This hook re-injects them

HINDSIGHT_URL="${HINDSIGHT_URL:-http://localhost:8888}"

echo "## Post-Compaction Re-injection"
echo ""

# Re-inject git context (Layer 3)
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "### Git (re-injected)"
  echo "**Branch:** $(git branch --show-current 2>/dev/null)"
  echo "**Last 3 commits:**"
  git log --oneline -3 2>/dev/null
  MODIFIED=$(git status --short 2>/dev/null)
  if [ -n "$MODIFIED" ]; then
    echo "**Modified:** $MODIFIED"
  fi
  echo ""
fi

# Re-inject Hindsight patterns (Layer 4) -- top 5 only
RECALL_JSON=$(curl -sf -m 5 -X POST "$HINDSIGHT_URL/v1/default/banks/claude-sessions/memories/recall" \
  -H 'Content-Type: application/json' \
  -d '{"query": "corrections and mistakes to avoid", "n": 5}' \
  2>/dev/null)

if [ -n "$RECALL_JSON" ] && [ "$RECALL_JSON" != "null" ]; then
  PATTERNS=$(echo "$RECALL_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    seen = set()
    for r in data.get('results', [])[:5]:
        t = r.get('text', '')
        if t and t not in seen:
            seen.add(t)
            print(f'- {t}')
except: pass
" 2>/dev/null)

  if [ -n "$PATTERNS" ]; then
    echo "### Critical Patterns (re-injected)"
    echo "$PATTERNS"
    echo ""
  fi
fi

# Re-inject active gates as reminders
if [ -f "$HOME/.claude/gates.json" ]; then
  GATE_LIST=$(python3 -c "
import json
with open('$HOME/.claude/gates.json') as f:
    gates = json.load(f)
for g in gates.get('gates', []):
    if g.get('enabled', True) and g.get('level') == 'block':
        print(f'- BLOCKED: {g[\"message\"]}')
" 2>/dev/null)

  if [ -n "$GATE_LIST" ]; then
    echo "### Active Gates (enforced by hooks)"
    echo "$GATE_LIST"
    echo ""
  fi
fi

exit 0
