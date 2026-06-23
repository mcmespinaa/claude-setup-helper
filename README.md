# claude-setup-helper

A Claude Code plugin that gets a clean, safe Claude setup onto any machine or project — and keeps it healthy. Everything runs **through Claude** via four skills; there are no scripts to run from a terminal.

## What it does

| Skill | Invoke | Does |
|-------|--------|------|
| **setup-onboard** | `/setup-onboard` | Installs the safety hooks, wires them into `settings.json` via a **non-destructive merge** (existing values always win), optionally copies skills/commands from a source you point at, and registers MCP servers. |
| **setup-audit** | `/setup-audit` | Read-only health check of `settings.json`, hooks, skills, commands, and MCP registration. Reports pass/warn/fail with concrete fixes. |
| **setup-config-wizard** | `/setup-config-wizard` | Guided, conversational tuning of `settings.json` — permissions, hooks, env, output style — one trade-off at a time. |
| **setup-scaffold** | `/setup-scaffold` | Generates an ICM folder structure for a project: Layer-0 `CLAUDE.md` map, Layer-1 `CONTEXT.md` rooms, optional Layer-2 stage contracts. |

## Safety model

- **`settings.json` is never overwritten.** It's backed up (`settings.json.bak.<timestamp>`) and merged. The merge is **additive, existing-wins**: your values are never removed, the template only adds what's missing, arrays are unioned and deduped, and re-runs never stack duplicate hooks. (Recipe verified — see `skills/setup-onboard/SKILL.md`.)
- **No file is clobbered** without showing you the conflict first.
- **No secrets.** The bundled `env-file-guard` hook blocks `.env`/`.key`/`.pem`/credential access, and no skill writes tokens into config.

## Install

This repo is a plugin marketplace. Add it, then enable the `claude-setup` plugin:

```
/plugin marketplace add mcmespinaa/claude-setup-helper
/plugin install claude-setup@claude-setup-helper
```

Then run `/setup-onboard` on a fresh machine, or `/setup-audit` to check an existing one.

## Layout

```
.claude-plugin/marketplace.json      # marketplace manifest
plugins/claude-setup/
  .claude-plugin/plugin.json         # plugin manifest
  skills/                            # the four skills above
  templates/
    hooks/                           # block-destructive.sh, env-file-guard.sh
    settings.template.json           # safe baseline (hooks pre-wired)
    icm/                             # CLAUDE.md + CONTEXT.md scaffolds
```

## Customizing what gets installed

`setup-onboard` does **not** bundle personal skills/commands. To replicate yours, point it at a source tree (e.g. another machine's `~/.claude/skills`) when it asks. This keeps the plugin generic and small.

---

MIT · maintained by [@mcmespinaa](https://github.com/mcmespinaa)
