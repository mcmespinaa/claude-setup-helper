---
name: setup-config-wizard
description: "Interactively tune ~/.claude/settings.json — permissions, hooks, env vars, and output style — through a guided conversation. Use when the user says /setup-config-wizard, 'help me configure settings.json', 'set up my permissions', 'add an allow rule', 'reduce permission prompts', 'turn on a hook', or 'what should my Claude settings be'. Explains each trade-off before changing it, edits settings.json in place with a backup, and validates the JSON after every write. NOT for first-time install of hooks/skills (use /setup-onboard) or read-only checking (use /setup-audit)."
---

# setup-config-wizard

Guide the user through their `~/.claude/settings.json` one decision at a time. Unlike onboard (which installs a baseline) this is conversational: surface a choice, explain the trade-off, apply only what they pick.

## Rules

- **Back up before the first edit** this session (`settings.json.bak.<timestamp>`), then edit in place.
- **Validate after every write** (`jq . settings.json`). If a write produces invalid JSON, restore from the backup and report.
- **Never add a permission the user didn't ask for**, and never broaden a path wildcard beyond what they intend. When adding an `allow` rule, show the exact string first and confirm.
- **Never write secrets** into `env`. If a value looks like a token/key, refuse and tell them to set it as a real environment variable.

## Topics to offer (pick what's relevant — don't force all)

1. **Permissions / fewer prompts.** If they're tired of approval prompts, look at what they actually run and propose tight `allow` rules (prefer specific `Bash(tool subcommand:*)` over broad `Bash(*)`). Explain: each allow rule trades a prompt for standing trust — scope it as narrowly as the workflow allows.
2. **Hooks.** Offer to enable PreToolUse safety hooks (block-destructive, env-file-guard) if not wired, or add a Stop hook. Explain matchers (`Bash`, `Read|Edit|Write`) and that `exit 2` is a hard block.
3. **Env vars.** Non-secret config only (e.g. feature flags). Explain these are passed to every tool invocation.
4. **Output style / model.** Mention `/config` and `/output-style` as the lighter-weight UI for these; only edit settings.json directly if they prefer.

## Process

1. Read the current `settings.json` (or note there isn't one and offer to create from the plugin template).
2. Ask which topic they want, or infer from their request.
3. For each change: state it, explain the trade-off in one or two lines, show the exact JSON diff, confirm, write, validate.
4. At the end, summarize what changed and suggest `/setup-audit` to confirm everything resolves.

## Editing technique

Prefer `jq` for structural edits (adding to `permissions.allow`, inserting a hook) over hand-editing, so you can't corrupt the file. Example — add an allow rule, deduped:

```bash
jq --arg rule "Bash(git status)" \
  '.permissions.allow = ((.permissions.allow // []) + [$rule] | unique_by(.))' \
  ~/.claude/settings.json
```
Always write to a temp file, `jq .` it, then move into place — never redirect over the file you're reading.
