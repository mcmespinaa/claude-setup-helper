# Evals

Behavioral regression suite for the `claude-setup` plugin. Verifies the **deterministic behaviors the skills promise** — the dangerous paths — against a throwaway sandbox. **It never touches your real `~/.claude`.**

## Run

```bash
./evals/run-evals.sh        # exit 0 = all pass, 1 = a failure
```

Requires `jq`. The harness creates a temp `CLAUDE_HOME` (auto-removed on exit) and runs the exact operations the skills prescribe against it.

## What it checks

| Eval | Skill | Asserts |
|------|-------|---------|
| 0 | — | The jq merge recipe in the harness is **identical** to the one in `setup-onboard/SKILL.md` (no doc/code drift). |
| 1 | onboard | Fresh machine: template copied → valid JSON, both safety hooks wired. |
| 2 | onboard | Existing config: merged not overwritten, **existing values win**, permissions unioned, env-file-guard appended without duplicating block-destructive, backup made. |
| 3 | onboard | **Idempotent** — a second merge is a byte-identical no-op. |
| 4 | onboard | **Never clobbers** a user's customized hook file. |
| 5 | audit | The read-only check **detects a wired-but-missing hook** (the #1 "hook isn't firing" cause). |
| 6 | scaffold | Filling the ICM `CLAUDE.md` template leaves **no unfilled `{{tokens}}`**. |

## Scope & honesty

These are **deterministic behavioral evals**: they test the file-level operations the skills depend on (the jq merge, idempotency, no-clobber copies, token-fill), extracted from the skills so a regression fails loudly.

They do **not** test skill *triggering* (does "check my config" route to `setup-audit`?) — that needs a model-in-the-loop run and isn't deterministic. Nor do they drive a real agent end-to-end. If you change a skill's procedure, mirror it here so Eval 0's drift check stays green.

## Adding a case

Add a new `grp "Eval N — ..."` block in `run-evals.sh`, operate on `$CLAUDE_HOME` (the sandbox), and assert with `ok`/`no`. Keep every mutation inside `$CLAUDE_HOME` or `$SANDBOX` so the real home is never touched.
