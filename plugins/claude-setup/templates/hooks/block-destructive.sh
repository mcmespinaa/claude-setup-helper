#!/bin/bash
# block-destructive.sh -- Global PreToolUse hook
# Blocks destructive commands that are hard to reverse.
# Exit 2 = hard block. Exit 0 = allow.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check Bash commands
if [ "$TOOL" != "Bash" ]; then
  exit 0
fi

# Block patterns
BLOCKED_PATTERNS=(
  "rm -rf /"
  "rm -rf ~"
  "rm -rf \."
  "git push --force"
  "git push -f "
  "git reset --hard"
  "git clean -fd"
  "DROP TABLE"
  "DROP DATABASE"
  "TRUNCATE "
  "DELETE FROM"
  "docker system prune -a"
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qi "$pattern"; then
    echo "Blocked: destructive command detected -- '$pattern'. This requires manual execution." >&2
    exit 2
  fi
done

exit 0
