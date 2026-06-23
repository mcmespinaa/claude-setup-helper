# claude-setup-helper

A Claude Code plugin that gets a clean, safe Claude Code setup onto **any** machine or project — and keeps it healthy. Everything runs **through an agent** (Claude Code or compatible) via four skills; there are no scripts to run from a terminal.

> **This README is an implementation runbook for an AI agent.** If you are an agent installing this on a user's computer, read it top-to-bottom and follow it literally. It assumes nothing about the target machine. Human readers: the [Quick start](#quick-start-for-humans) is near the top; the rest is the agent procedure.

---

## What it does

| Skill | Invoke | Job |
|-------|--------|-----|
| **setup-onboard** | `/setup-onboard` | Install safety hooks, wire them into `settings.json` via a **non-destructive merge**, optionally copy skills/commands from a source the user points at, and register MCP servers. |
| **setup-audit** | `/setup-audit` | Read-only health check of `settings.json`, hooks, skills, commands, MCP. Reports pass/warn/fail with fixes. |
| **setup-config-wizard** | `/setup-config-wizard` | Guided, conversational tuning of `settings.json` (permissions, hooks, env). |
| **setup-scaffold** | `/setup-scaffold` | Generate an ICM folder structure for a project (CLAUDE.md map, CONTEXT.md rooms, stage contracts). |

---

## Quick start (for humans)

```text
/plugin marketplace add mcmespinaa/claude-setup-helper
/plugin install claude-setup@claude-setup-helper
/setup-onboard          # on a fresh machine
/setup-audit            # to check an existing one
```

Then read the agent runbook below if you want to understand exactly what the agent will do to your machine.

---

# Agent implementation runbook

You are an agent installing `claude-setup-helper` on a user's computer. Your job is to leave them with a working, safe Claude Code environment **without destroying anything they already have**. Follow this procedure.

## 0. Non-negotiable invariants

These hold for the entire procedure. Violating one is a failure even if the user "seems fine" with it.

1. **Never overwrite `~/.claude/settings.json`.** Back it up, merge, validate, then write. (§4)
2. **Never clobber an existing file** (hook, skill, command, CLAUDE.md) without showing the diff and getting an explicit "yes".
3. **Never read, print, copy, or commit** `.env`, `.key`, `.pem`, `credentials*`, `secrets*`, or service-account JSON. Not even to "check" them.
4. **Idempotent.** Running the procedure twice must not duplicate hooks, re-copy edited files, or double-merge.
5. **Confirm before each mutating step**, and offer a dry preview ("here's what I would change") first.
6. **Public-surface caution.** Do not push the user's `~/.claude` contents anywhere. This plugin replicates *structure and safety defaults*, not the user's private skills, unless they explicitly point you at a source.

If any step's verification fails, **stop and report** rather than pressing on.

## 1. Detect the environment (do this first, change nothing)

Gather facts before touching anything. Run read-only:

```bash
uname -s                                   # Darwin | Linux | (Windows: expect Git Bash/WSL)
command -v jq        || echo "NO jq"       # required for the settings merge
command -v claude    || echo "NO claude CLI"
command -v rsync     || echo "NO rsync"
command -v git       || echo "NO git"
echo "HOME=$HOME"
test -d "$HOME/.claude" && echo "has ~/.claude" || echo "no ~/.claude yet"
test -f "$HOME/.claude/settings.json" && echo "has settings.json" || echo "no settings.json"
ls -1 "$HOME/.claude/hooks" 2>/dev/null    # existing hooks, if any
```

Branch on the results:
- **`NO jq`** → the settings merge (§4) cannot run safely. Tell the user to install it (`brew install jq` on macOS, `apt-get install jq` / `sudo dnf install jq` on Linux) and **skip §4** until it's present. Everything else can still proceed.
- **`NO claude CLI`** → MCP registration (§6) becomes "print config for manual add", not automatic.
- **`NO rsync`** → skills/commands copy (§5) falls back to `cp -R` with manual conflict checks.
- **Windows without a POSIX shell** → the `.sh` hooks won't run. Note this to the user; hooks assume bash + `jq`. WSL or Git Bash is required for the hook scripts.

## 2. Locate this plugin's templates

The skills read from the plugin's `templates/` directory. Resolve it once and store as `TEMPLATES`:

- If installed via the marketplace, it's under the plugin install path (Claude Code exposes it; the skills receive it as `TEMPLATES`).
- If working from a clone: `TEMPLATES="$REPO/plugins/claude-setup/templates"`.

Confirm it has what you expect:

```bash
ls "$TEMPLATES"/hooks/*.sh "$TEMPLATES"/settings.template.json "$TEMPLATES"/icm/ 2>&1
```

Expected: `block-destructive.sh`, `env-file-guard.sh`, `settings.template.json`, `icm/CLAUDE.md`, `icm/CONTEXT.md`.

## 3. Install hooks

```bash
mkdir -p "$HOME/.claude/hooks"
for src in "$TEMPLATES"/hooks/*.sh; do
  name="$(basename "$src")"; dest="$HOME/.claude/hooks/$name"
  if [ -f "$dest" ]; then
    echo "EXISTS: $name — skipping (ask before overwriting)"
  else
    cp "$src" "$dest" && chmod +x "$dest" && echo "INSTALLED: $name"
  fi
done
```

- `block-destructive.sh` — blocks `rm -rf /`, `git push --force`, `git reset --hard`, `DROP TABLE`, etc. (PreToolUse, `exit 2` = hard block).
- `env-file-guard.sh` — blocks reads/writes of `.env`/`.key`/`.pem`/credential files.

If a hook already exists, **do not overwrite it** without diffing and confirming — the user may have customized it.

## 4. Merge `settings.json` (the careful step)

This is the highest-risk file: it holds `permissions`, `hooks`, `enabledPlugins`, and `env`. **Requires `jq`.**

**Case A — no `settings.json` exists:** copy the template verbatim.

```bash
cp "$TEMPLATES/settings.template.json" "$HOME/.claude/settings.json"
```

**Case B — one already exists:** back up → merge → validate → write.

```bash
SETTINGS="$HOME/.claude/settings.json"
BACKUP="$SETTINGS.bak.$(date +%s)"
cp "$SETTINGS" "$BACKUP"          # always back up first

existing="$SETTINGS"; template="$TEMPLATES/settings.template.json"
merged="$(jq -n --slurpfile e "$existing" --slurpfile t "$template" '
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
')"

# VALIDATE before writing — if this fails, the original is still intact.
if printf '%s\n' "$merged" | jq . >/dev/null 2>&1; then
  printf '%s\n' "$merged" > "$SETTINGS"
  echo "MERGED. Backup at $BACKUP"
else
  echo "MERGE PRODUCED INVALID JSON — left settings.json untouched. Backup at $BACKUP"
fi
```

**Merge policy: additive, existing always wins.** The template can only *add* what's missing. It never removes or overrides a value the user already has, arrays are unioned and deduped, and re-runs never stack duplicate hooks. (Verified behavior — see [`skills/setup-onboard/SKILL.md`](plugins/claude-setup/skills/setup-onboard/SKILL.md).)

**Rollback** (if anything looks wrong afterward):

```bash
cp "$HOME/.claude/settings.json.bak.<timestamp>" "$HOME/.claude/settings.json"
```

> For hook arrays beyond `PreToolUse` (e.g. `hooks.Stop`), apply the same `select(... | not)` append pattern per key.

## 5. Copy skills & commands (optional, only if the user provides a source)

Do **not** bundle or invent these. Ask the user for a source path (e.g. another machine's `~/.claude/skills`). Then, preserving their edits:

```bash
rsync -a --ignore-existing "$SRC_SKILLS/"   "$HOME/.claude/skills/"
rsync -a --ignore-existing "$SRC_COMMANDS/" "$HOME/.claude/commands/"
```

`--ignore-existing` means files the user already has are left untouched. Report added vs. skipped. (No `rsync`? Use `cp -Rn` for the same "don't clobber" behavior.)

## 6. Register MCP servers (optional)

Only if the user wants them and a `mcp.template.json` is present.
- **`claude` CLI available:** register each server with `claude mcp add ...`. **Never write auth tokens** — MCP authentication is the user's job; print the steps and let them authenticate.
- **No CLI:** print the server configs for the user to add manually.

## 7. Verify

Run `/setup-audit` (or its checks inline). Confirm:
- `settings.json` is valid JSON and has `permissions` + `hooks` blocks.
- Every hook referenced in `settings.json` exists on disk **and** is executable (`test -x`). A hook wired but missing is the #1 cause of "my hook isn't firing".
- `block-destructive.sh` and `env-file-guard.sh` are both present and wired.

```bash
jq . "$HOME/.claude/settings.json" >/dev/null && echo "settings.json valid"
for h in "$HOME"/.claude/hooks/*.sh; do test -x "$h" && echo "exec: $h" || echo "NOT EXEC: $h"; done
```

## 8. Close

Summarize: what was installed, what was skipped (and why), and the `settings.json` backup path. Point the user at `/setup-config-wizard` to tune permissions and `/setup-audit` to re-check anytime.

---

## Decision points the agent must surface (not decide silently)

| Decision | Default | When to ask |
|----------|---------|-------------|
| Overwrite an existing hook/skill/command | **No** (skip) | Always ask before overwriting anything the user already has. |
| Make a git repo of their config public | **Never** without explicit yes | Public visibility is irreversible and indexed. |
| Add a broad permission (e.g. `Bash(*)`) | **No** — prefer narrow `Bash(tool sub:*)` | Always; explain that each allow rule trades a prompt for standing trust. |
| Copy the user's private skills from elsewhere | **No** unless they give a path | Only on explicit source. Never assume a tree. |

---

## Safety model (why this is safe to run on someone else's machine)

- **`settings.json` is never overwritten** — backed up (`settings.json.bak.<timestamp>`) and additively merged; existing values always win; re-runs are idempotent.
- **No file is clobbered** without a shown diff and a yes.
- **No secrets** — the bundled `env-file-guard` hook blocks `.env`/`.key`/`.pem`/credential access, and no skill writes tokens into config.
- **Read-only by default** — `setup-audit` never mutates; the other skills confirm before each change and offer a dry preview.

## Evals

A behavioral regression suite verifies the dangerous paths (settings.json merge, idempotency, no-clobber, audit detection) against a sandbox — it never touches your real `~/.claude`:

```bash
./evals/run-evals.sh
```

See [`evals/README.md`](evals/README.md). Current status: **12/12 pass**.

## Repository layout

```
.claude-plugin/marketplace.json      # marketplace manifest (how /plugin finds it)
plugins/claude-setup/
  .claude-plugin/plugin.json         # plugin manifest
  skills/
    setup-onboard/SKILL.md           # install + merge (the runbook above, as a skill)
    setup-audit/SKILL.md             # read-only health check
    setup-config-wizard/SKILL.md     # guided settings.json tuning
    setup-scaffold/SKILL.md          # ICM project generator
  templates/
    hooks/                           # block-destructive.sh, env-file-guard.sh
    settings.template.json           # safe baseline, hooks pre-wired
    icm/                             # CLAUDE.md + CONTEXT.md scaffolds
```

## Requirements on the target machine

| Tool | Needed for | If missing |
|------|-----------|------------|
| `jq` | settings.json merge & audit | Install it; skip §4 until present |
| `bash` | running the `.sh` hooks | Hooks won't run (Windows: use WSL/Git Bash) |
| `claude` CLI | automatic MCP registration | MCP step prints manual config |
| `rsync` | skills/commands copy | Falls back to `cp -Rn` |

## Troubleshooting

- **"My hook isn't firing."** It's wired in `settings.json` but missing on disk or not executable. Run `/setup-audit`; fix with `chmod +x` or re-run `/setup-onboard`.
- **`settings.json` won't load.** Likely invalid JSON from a hand-edit. `jq . ~/.claude/settings.json` shows the error; restore from the newest `.bak.*`.
- **Merge "did nothing".** Expected when the template's values already exist — the merge is additive, so a fully-configured machine sees no change. That's correct, not a bug.

---

MIT · maintained by [@mcmespinaa](https://github.com/mcmespinaa)
