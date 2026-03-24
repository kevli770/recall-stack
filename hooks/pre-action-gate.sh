#!/bin/bash
# Pre-Action Gate -- blocks known-bad patterns before tool execution
# Reads gates.json, checks tool_name + input against patterns
# Exit 0 = allow, Exit 2 = block (with stderr message)

GATES_FILE="$HOME/.claude/gates.json"
[ ! -f "$GATES_FILE" ] && exit 0

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('tool_name',''))" 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | python3 -c "import json,sys;d=json.load(sys.stdin);print(json.dumps(d.get('tool_input',{})))" 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

RESULT=$(python3 -c "
import json, sys, re, os

with open(os.path.expanduser('~/.claude/gates.json')) as f:
    gates = json.load(f)

tool = '$TOOL_NAME'
tool_input = sys.stdin.read()

for gate in gates.get('gates', []):
    if not gate.get('enabled', True):
        continue
    tool_pattern = gate.get('tool', '*')
    if tool_pattern != '*' and tool_pattern != tool:
        if not re.search(tool_pattern, tool):
            continue
    input_pattern = gate.get('pattern', '')
    if input_pattern and not re.search(input_pattern, tool_input, re.IGNORECASE):
        continue
    level = gate.get('level', 'warn')
    message = gate.get('message', 'Blocked by gate')
    if level == 'block':
        print(f'BLOCK|{message}')
        sys.exit(0)
    elif level == 'warn':
        print(f'WARN|{message}')
        sys.exit(0)
print('ALLOW|')
" <<< "$TOOL_INPUT" 2>/dev/null)

ACTION=$(echo "$RESULT" | cut -d'|' -f1)
MESSAGE=$(echo "$RESULT" | cut -d'|' -f2-)

if [ "$ACTION" = "BLOCK" ]; then
  echo "GATE BLOCKED: $MESSAGE" >&2
  exit 2
elif [ "$ACTION" = "WARN" ]; then
  echo "GATE WARNING: $MESSAGE" >&2
fi

exit 0
