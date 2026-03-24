#!/bin/bash
# Layer 4: Fires on Claude Code session end
# 1. Stores session summary in Hindsight
# 2. Auto-tracks failures from lessons.md and promotes to gates after 3 occurrences

HINDSIGHT_URL="${HINDSIGHT_URL:-http://localhost:8888}"
FAILURES_FILE="$HOME/.claude/failures.json"
GATES_FILE="$HOME/.claude/gates.json"

# --- Hindsight retain ---
BRANCH=""
LAST_COMMIT=""
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null)
  LAST_COMMIT=$(git log -1 --pretty='%s' 2>/dev/null)
fi

CONTENT="Session ended $(date). Branch: ${BRANCH:-none}. Last commit: ${LAST_COMMIT:-none}."

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

# --- Auto-failure tracking ---
[ ! -f "$GATES_FILE" ] && exit 0
[ ! -f "$FAILURES_FILE" ] && echo '{"failures":{}}' > "$FAILURES_FILE"

python3 << 'PYEOF'
import json, re, os, sys

failures_file = os.path.expanduser("~/.claude/failures.json")
gates_file = os.path.expanduser("~/.claude/gates.json")

# Find all lessons.md files across projects
lessons_paths = []
projects_dir = os.path.expanduser("~/.claude/projects")
if os.path.isdir(projects_dir):
    for root, dirs, files in os.walk(projects_dir):
        if "lessons.md" in files:
            lessons_paths.append(os.path.join(root, "lessons.md"))

if not lessons_paths:
    sys.exit(0)

try:
    with open(failures_file) as f:
        data = json.load(f)
except:
    data = {"failures": {}}

try:
    with open(gates_file) as f:
        gates = json.load(f)
except:
    sys.exit(0)

changed = False
for lpath in lessons_paths:
    try:
        with open(lpath) as f:
            lines = f.readlines()
    except:
        continue

    for line in lines:
        # Match: [date] | what went wrong | rule to follow
        m = re.match(r'\[([^\]]+)\]\s*\|\s*(.+?)\s*\|\s*(.+)', line.strip())
        if not m:
            continue

        lesson_date, mistake, rule = m.groups()
        key = re.sub(r'[^a-z0-9 ]', '', rule.lower()).strip()[:50]
        if not key:
            continue

        if key not in data["failures"]:
            data["failures"][key] = {"count": 0, "rule": rule.strip(), "mistake": mistake.strip(), "promoted": False}
        data["failures"][key]["count"] += 1
        changed = True

        # Auto-promote to warning gate after 3 occurrences
        if data["failures"][key]["count"] >= 3 and not data["failures"][key]["promoted"]:
            gate_name = "auto-" + key.replace(" ", "-")[:30]
            existing = [g for g in gates.get("gates", []) if g.get("name") == gate_name]
            if not existing:
                gates["gates"].append({
                    "name": gate_name,
                    "tool": "*",
                    "pattern": "",
                    "level": "warn",
                    "message": "Repeated mistake (3x): " + rule.strip()[:80],
                    "enabled": True,
                    "auto": True
                })
                data["failures"][key]["promoted"] = True

if changed:
    with open(failures_file, 'w') as f:
        json.dump(data, f, indent=2)
    with open(gates_file, 'w') as f:
        json.dump(gates, f, indent=2)

PYEOF

exit 0
