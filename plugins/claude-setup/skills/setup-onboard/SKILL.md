---
name: setup-onboard
description: "Onboard Claude Code onto a new machine or a fresh account. Use when the user says /setup-onboard, 'set up Claude Code on this machine', 'install my hooks/skills/commands', 'get Claude configured', or has just installed the claude-setup plugin and wants their environment wired up. Installs the safety hooks (block-destructive, env-file-guard), wires them into settings.json via a non-destructive merge, optionally copies skills/commands from a source the user points at, and registers MCP servers. Idempotent and non-destructive: settings.json is always backed up and merged (never overwritten), and existing files are never clobbered without explicit confirmation. NOT for auditing an existing setup (use /setup-audit), tuning settings interactively (use /setup-config-wizard), or creating a project's folder structure (use /setup-scaffold)."
---

# setup-onboard

Wire up a working, safe Claude Code environment on this machine. You do the work through Bash/Read/Write tool calls — there is no external script. Be careful: you are editing the user's `~/.claude`.

## Hard rules (do not violate)

1. **Never overwrite `settings.json`.** Always back it up first (`settings.json.bak.<timestamp>`), then merge. Validate the merged result is valid JSON with `jq .` before writing. If the merge is invalid, leave the original untouched and report the backup path.
2. **Never clobber an existing file** (hook, skill, command) without showing the user the conflict and getting a yes.
3. **Never read or print `.env`, `.key`, `.pem`, or credential files** — the env-file-guard hook exists for exactly this; respect it.
4. **Idempotent.** Re-running must not duplicate hook entries in `settings.json` or re-copy files the user has since edited.
5. Confirm before each component. Offer a "show me what would change first" (dry preview) every time.

## Inputs

- `TEMPLATES` = this plugin's `templates/` directory (hooks, `settings.template.json`, ICM templates).
- Optionally, a **source tree** the user points at for their personal skills/commands (e.g. another machine's `~/.claude/skills`). Do not bundle or assume these — ask for the path.

## Process

Work through these components, confirming each. Skip any the user declines.

### 1. Preflight
- Confirm `jq` is installed (`command -v jq`). If not, tell the user to `brew install jq` (the settings merge needs it) and stop the settings step.
- Ensure `~/.claude/` and `~/.claude/hooks/` exist (`mkdir -p`).

### 2. Hooks
- For each `*.sh` in `TEMPLATES/hooks/`: if it already exists in `~/.claude/hooks/`, report and skip (unless the user says overwrite). Otherwise copy it and `chmod +x`.

### 3. settings.json — the careful one
This is the highest-risk file. It holds `permissions`, `hooks`, `enabledPlugins`, and `env`.

- If **no** `~/.claude/settings.json` exists: copy `TEMPLATES/settings.template.json` to it. Done.
- If one **exists**:
  1. Back it up to `settings.json.bak.<unix-timestamp>`.
  2. Merge the template into it using the **merge policy** below.
  3. Validate with `jq .`; if invalid, restore nothing (original is untouched) and report.
  4. Write the merged result and report the backup path.

#### Merge policy — additive only (existing always wins)

The user's existing config is sacred. The template may only **add** what is missing; it must never remove or override a value the user already has. This makes onboarding safe to run on a machine that's already partly configured — running it can never take anything away.

Rules:
- **Scalars / objects (`env`, `permissions.additionalDirectories`, any key):** if the existing file has the key, keep the existing value verbatim. Only pull in template keys the existing file lacks.
- **Arrays (`permissions.allow`):** union the two, dedupe exact-equal entries, preserve existing order first.
- **`hooks` blocks (`PreToolUse[]`, `Stop[]`, etc.):** append only template hook entries whose `(matcher, command)` pair is not already present. Never duplicate, never reorder existing ones.

Reference `jq` recipe (tested). The `*` operator does "recursive object merge, right side wins" — so `template * existing` makes **existing win** on every scalar/object key, and we then fix up the two arrays we care about with explicit union + dedupe:

```bash
jq -n --slurpfile e "$existing" --slurpfile t "$template" '
  ($e[0]) as $E | ($t[0]) as $T
  | ($T * $E) as $base                      # existing wins on every scalar/object key
  | $base
  | .permissions.allow =
      ((($T.permissions.allow // []) + ($E.permissions.allow // [])) | unique_by(.))
  | .hooks.PreToolUse =
      (($E.hooks.PreToolUse // [])           # existing entries first, untouched
       + [ ($T.hooks.PreToolUse // [])[]      # append only template entries not already present
           | select( . as $h
               | (($E.hooks.PreToolUse // []) | any(. == $h)) | not ) ])
'
```
Verified behavior: existing scalar values are kept (template overrides rejected), template-only keys are added, `permissions.allow` is unioned with duplicates collapsed, and an identical hook entry is **not** duplicated on re-run while a genuinely new one is appended.

> For hook arrays beyond `PreToolUse` (e.g. `hooks.Stop`), apply the same `select(... | not)` append pattern per key. Always pipe the final output through `jq .` to confirm validity before writing, and keep the timestamped backup.

### 4. Skills & commands (optional)
- Only if the user provides a source path. Use `rsync -a --ignore-existing <src>/ ~/.claude/skills/` so user edits survive. Report what was added vs. skipped.

### 5. MCP servers (optional)
- If `TEMPLATES/mcp.template.json` exists and the user wants them: for each server, register via the `claude mcp add` CLI if available, else print the config for the user to add manually. Never write tokens — MCP auth is the user's job.

## Output / close
- Summarize what changed (installed / skipped / backed up), with the backup path for settings.json.
- Point the user at `/setup-audit` to verify, and `/setup-config-wizard` to tune permissions.
