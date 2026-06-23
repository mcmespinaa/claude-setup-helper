#!/bin/bash
# env-file-guard.sh -- Global PreToolUse hook
# Blocks access to .env files, credentials, and API keys.
# Exit 2 = hard block. Exit 0 = allow.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Check file read/write operations
if [ "$TOOL" = "Read" ] || [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  # Block .env files
  if echo "$FILE_PATH" | grep -qE '\.env($|\.)'; then
    echo "Blocked: cannot access .env files. Environment variables must be managed manually." >&2
    exit 2
  fi

  # Block known credential files
  if echo "$FILE_PATH" | grep -qiE '(credentials|secrets|\.key$|\.pem$|service.account\.json|firebase.*key)'; then
    echo "Blocked: cannot access credential/key files." >&2
    exit 2
  fi
fi

# Check Bash for cat/echo of env files or printing secrets
if [ "$TOOL" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  if echo "$COMMAND" | grep -qE '(cat|head|tail|less|more|echo.*\$).*\.env'; then
    echo "Blocked: cannot read .env files via shell commands." >&2
    exit 2
  fi
fi

exit 0
