---
name: setup-audit
description: "Validate an existing Claude Code setup and report what's missing or broken. Use when the user says /setup-audit, 'check my Claude setup', 'is my config correct', 'why isn't my hook firing', 'verify my settings', or after /setup-onboard to confirm the result. Read-only: inspects ~/.claude/settings.json, ~/.claude/hooks, skills, commands, and MCP registration, then reports a checklist of pass/warn/fail with concrete fixes. Never modifies anything. NOT for installing missing pieces (use /setup-onboard) or interactively editing settings (use /setup-config-wizard)."
---

# setup-audit

Diagnose a Claude Code setup. **Read-only — you must not modify any file.** Produce a clear pass / warn / fail checklist with a one-line fix for each non-pass.

## What to check

Run these checks (Bash + Read only), then report.

### 1. settings.json validity
- Exists at `~/.claude/settings.json`? (`test -f`)
- Valid JSON? (`jq . ~/.claude/settings.json` — report the parse error verbatim if it fails; an invalid settings.json silently disables features).
- Has a `permissions` block and a `hooks` block?

### 2. Hooks wired AND present
For each hook referenced in `settings.json` (`jq -r '.. | .command? // empty'`), resolve `$HOME`/`$CLAUDE_PROJECT_DIR` and check the file:
- **exists** on disk,
- is **executable** (`test -x`),
- (warn) starts with a shebang.
A hook wired in settings but missing on disk is the #1 cause of "my hook isn't firing" — flag it loudly.

### 3. Recommended safety hooks
- Is `block-destructive.sh` referenced and present? (warn if absent)
- Is `env-file-guard.sh` referenced and present? (warn if absent)

### 4. Skills & commands
- Count `~/.claude/skills/*/SKILL.md` and `~/.claude/commands/*.md`. Report the counts.
- (warn) Any skill directory missing a `SKILL.md`, or any `SKILL.md` missing a `name:`/`description:` frontmatter pair.

### 5. MCP servers
- If the `claude` CLI is present, `claude mcp list` and report registered servers. Otherwise note it can't be checked and move on. Never print tokens or auth values.

### 6. Tooling
- `jq` on PATH? (fail — settings merge/audit needs it.)

## Output format

A compact checklist. Use ✓ / ! / ✗ and group by section. End with a **Top fixes** list (only the ✗ and the most important !), each as a single actionable line — e.g. "✗ `env-file-guard.sh` wired in settings but not on disk → run /setup-onboard, or copy it from the plugin's templates/hooks/."

Do not propose running fixes yourself — this skill only reports. Point the user at /setup-onboard or /setup-config-wizard to act.
