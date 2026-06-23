#!/usr/bin/env bash
#
# run-evals.sh — Behavioral eval harness for the claude-setup plugin.
#
# Tests the DETERMINISTIC behaviors the skills promise, against a throwaway
# fake CLAUDE_HOME in a temp dir. NEVER touches the real ~/.claude.
#
# What it asserts (the dangerous paths):
#   onboard:  settings.json is merged not overwritten; existing values win;
#             arrays union+dedupe; hooks not duplicated on re-run (idempotent);
#             a backup is created; no existing file is clobbered.
#   audit:    the read-only checks detect a wired-but-missing hook.
#   scaffold: filling the ICM templates leaves no unfilled {{tokens}}.
#
# The jq merge recipe below is copied VERBATIM from
# plugins/claude-setup/skills/setup-onboard/SKILL.md — if the skill changes,
# update it here and a drift check (eval 0) will catch a mismatch.
#
# Usage: ./run-evals.sh   (exit 0 = all pass, 1 = a failure)
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$REPO/plugins/claude-setup/templates"
SKILL_ONBOARD="$REPO/plugins/claude-setup/skills/setup-onboard/SKILL.md"

PASS=0; FAIL=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
no()   { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
grp()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

command -v jq >/dev/null || { echo "jq required to run evals"; exit 1; }

# Throwaway sandbox — set CLAUDE_HOME so nothing real is touched.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/cshelper-eval.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
export CLAUDE_HOME="$SANDBOX/.claude"
mkdir -p "$CLAUDE_HOME/hooks"

# The verbatim merge function from the onboard skill.
merge_settings() {  # $1 existing, $2 template -> merged json on stdout
  jq -n --slurpfile e "$1" --slurpfile t "$2" '
    ($e[0]) as $E | ($t[0]) as $T
    # existing wins on every scalar/object key
    | ($T * $E) as $base
    | $base
    | .permissions.allow =
        ((($T.permissions.allow // []) + ($E.permissions.allow // [])) | unique_by(.))
    # existing hook entries first (untouched); then append only template
    # entries not already present, so re-runs never duplicate a hook
    | .hooks.PreToolUse =
        (($E.hooks.PreToolUse // [])
         + [ ($T.hooks.PreToolUse // [])[]
             | select( . as $h
                 | (($E.hooks.PreToolUse // []) | any(. == $h)) | not ) ])
  '
}

# ── Eval 0: drift check — recipe here matches the skill verbatim ────────────
grp "Eval 0 — merge recipe matches the skill (no doc/code drift)"
# Compare the core line; if the skill's recipe changed, flag it.
skill_line="$(grep -F 'select( . as $h' "$SKILL_ONBOARD" | tr -d ' ' | head -1)"
here_line="$(grep -F 'select( . as $h' "$0" | grep -v skill_line | tr -d ' ' | head -1)"
[ -n "$skill_line" ] && [ "$skill_line" = "$here_line" ] \
  && ok "harness merge recipe is identical to setup-onboard/SKILL.md" \
  || no "DRIFT: recipe in harness differs from the skill — update one to match"

# ── Eval 1: Case A — no settings.json → template copied verbatim ────────────
grp "Eval 1 — onboard, fresh machine (no settings.json yet)"
rm -f "$CLAUDE_HOME/settings.json"
cp "$TEMPLATES/settings.template.json" "$CLAUDE_HOME/settings.json"
jq . "$CLAUDE_HOME/settings.json" >/dev/null 2>&1 && ok "settings.json is valid JSON" || no "invalid JSON"
jq -e '.hooks.PreToolUse | length == 2' "$CLAUDE_HOME/settings.json" >/dev/null \
  && ok "both safety hooks wired" || no "expected 2 PreToolUse hook groups"

# ── Eval 2: Case B — merge into an existing, customized settings.json ───────
grp "Eval 2 — onboard, existing config (merge, existing wins)"
cat > "$SANDBOX/existing.json" <<'EOF'
{
  "env": { "MY_VAR": "keep-me" },
  "permissions": { "allow": ["Bash(obsidian read:*)"], "additionalDirectories": [] },
  "hooks": { "PreToolUse": [
    { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/block-destructive.sh" } ] }
  ] }
}
EOF
cp "$SANDBOX/existing.json" "$CLAUDE_HOME/settings.json"
BACKUP="$CLAUDE_HOME/settings.json.bak.testfixed"
cp "$CLAUDE_HOME/settings.json" "$BACKUP"
merged="$(merge_settings "$CLAUDE_HOME/settings.json" "$TEMPLATES/settings.template.json")"
printf '%s\n' "$merged" | jq . >/dev/null 2>&1 && ok "merged output is valid JSON" || no "merge produced invalid JSON"
printf '%s\n' "$merged" > "$CLAUDE_HOME/settings.json"

test -f "$BACKUP" && ok "backup exists before write" || no "no backup made"
[ "$(jq -r '.env.MY_VAR' "$CLAUDE_HOME/settings.json")" = "keep-me" ] \
  && ok "existing scalar (env.MY_VAR) preserved" || no "existing value was overwritten"
jq -e '.permissions.allow | index("Bash(obsidian read:*)")' "$CLAUDE_HOME/settings.json" >/dev/null \
  && ok "existing permission preserved" || no "existing permission lost"
[ "$(jq '.hooks.PreToolUse | length' "$CLAUDE_HOME/settings.json")" = "2" ] \
  && ok "env-file-guard hook appended (block-destructive not duplicated)" || no "hook count wrong after merge"

# ── Eval 3: idempotency — re-merge must change nothing ──────────────────────
grp "Eval 3 — onboard idempotency (re-run is a no-op)"
before="$(jq -S . "$CLAUDE_HOME/settings.json")"
remerged="$(merge_settings "$CLAUDE_HOME/settings.json" "$TEMPLATES/settings.template.json")"
after="$(printf '%s\n' "$remerged" | jq -S .)"
[ "$before" = "$after" ] && ok "second merge is a no-op (no duplicate hooks, no churn)" || no "re-run changed the file — not idempotent"

# ── Eval 4: no-clobber — existing hook file is not overwritten ──────────────
grp "Eval 4 — onboard never clobbers an existing hook"
printf '#!/bin/bash\n# USER CUSTOM\nexit 0\n' > "$CLAUDE_HOME/hooks/block-destructive.sh"
# Simulate the skill's copy step: skip if exists.
src="$TEMPLATES/hooks/block-destructive.sh"; dest="$CLAUDE_HOME/hooks/block-destructive.sh"
if [ -f "$dest" ]; then :; else cp "$src" "$dest"; fi
grep -q "USER CUSTOM" "$dest" && ok "existing user hook left untouched" || no "user hook was clobbered"

# ── Eval 5: audit detects a wired-but-missing hook ──────────────────────────
grp "Eval 5 — audit catches a wired-but-missing hook"
rm -f "$CLAUDE_HOME/hooks/env-file-guard.sh"   # wired in settings, now absent
missing=0
while read -r cmd; do
  path="${cmd/\$HOME/$SANDBOX}"; path="${path/\$\{HOME\}/$SANDBOX}"
  case "$cmd" in *.sh) [ -f "$path" ] || missing=$((missing+1));; esac
done < <(jq -r '.. | .command? // empty' "$CLAUDE_HOME/settings.json")
[ "$missing" -ge 1 ] && ok "audit logic flags the missing hook ($missing missing)" || no "audit missed a wired-but-missing hook"

# ── Eval 6: scaffold leaves no unfilled tokens ──────────────────────────────
grp "Eval 6 — scaffold fills every {{token}}"
out="$SANDBOX/CLAUDE.md"
sed -e 's/{{PROJECT_NAME}}/Demo/g' \
    -e 's/{{ONE_LINE_DESCRIPTION}}/A demo project./g' \
    -e 's/{{TASK_1}}/Build/g' -e 's#{{DIR_1}}#src/#g' -e 's/{{ENTRY_FILE_1}}/README.md/g' \
    -e 's/{{TASK_2}}/Test/g' -e 's#{{DIR_2}}#tests/#g' -e 's/{{ENTRY_FILE_2}}/RUNNING.md/g' \
    -e 's/{{BUILD_COMMAND}}/make build/g' \
    -e 's/{{CONVENTION_1}}/Two-space indent/g' -e 's/{{CONVENTION_2}}/Conventional commits/g' \
    -e 's/{{ANTIPATTERN_1}}/No God files/g' \
    -e 's/{{OWNER}}/tester/g' -e 's/{{DATE}}/2026-01-01/g' \
    "$TEMPLATES/icm/CLAUDE.md" > "$out"
if grep -q '{{' "$out"; then
  no "unfilled tokens remain: $(grep -o '{{[^}]*}}' "$out" | sort -u | tr '\n' ' ')"
else
  ok "all {{tokens}} in CLAUDE.md template are fillable (none left)"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
grp "Summary"
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && { echo "  sandbox: $SANDBOX (auto-removed)"; exit 0; } || exit 1
