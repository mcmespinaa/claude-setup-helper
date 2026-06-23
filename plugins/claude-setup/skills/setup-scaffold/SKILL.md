---
name: setup-scaffold
description: "Scaffold an ICM-structured project so Claude Code works well in it from day one. Use when the user says /setup-scaffold, 'set up a new project for Claude', 'create a CLAUDE.md', 'scaffold this repo', 'give this project the ICM structure', or starts a fresh project and wants the folder architecture. Interviews the user briefly, then generates a Layer-0 CLAUDE.md (map), Layer-1 CONTEXT.md rooms for each folder, and optional Layer-2 stage contracts, filling the plugin's ICM templates with real answers. Idempotent: never overwrites an existing CLAUDE.md/CONTEXT.md without confirmation. NOT for configuring ~/.claude itself (use /setup-onboard or /setup-config-wizard)."
---

# setup-scaffold

Generate the ICM (Inverted Context Management) folder structure for a project so Claude has a map (Layer 0), rooms (Layer 1), and — where it's a pipeline — stage contracts (Layer 2). Source the structure from this plugin's `templates/icm/` and fill the `{{TOKENS}}` from a short interview.

## The ICM layers you're creating

- **Layer 0 — `CLAUDE.md` at the project root.** The map. Short, routes outward, lists build commands and conventions. One per project.
- **Layer 1 — `CONTEXT.md` per significant folder.** A room. Scopes that folder, states its boundaries.
- **Layer 2 — Stage Contract** (inside a CONTEXT.md). Only for folders that are pipeline stages: Inputs / Process / Outputs / Review checkpoint.

This mirrors what `/folder-audit` grades, so a scaffolded project should pass that audit.

## Rules

- **Never overwrite** an existing `CLAUDE.md` or `CONTEXT.md` without showing the user and confirming. Offer to write `CLAUDE.proposed.md` instead if they want to compare.
- **No unfilled placeholders.** After writing, grep the output for `{{` — if any token is unfilled, either ask the user or remove that line. Don't ship a file with `{{TASK_1}}` in it.
- **Only create rooms that earn one.** Don't drop a CONTEXT.md into every empty folder; add one where a folder has its own concern or >~10 files (same threshold the workspace conventions use).

## Process

1. **Interview** (keep it to 4–6 questions):
   - Project name + one-line description.
   - Is it a single codebase, or a staged pipeline? (decides whether to add Layer-2 contracts)
   - Main build/run command.
   - 2–3 top-level folders and what each is for (becomes the routing table + rooms).
   - 1–2 conventions and 1 anti-pattern worth recording.
2. **Generate Layer 0:** read `templates/icm/CLAUDE.md`, fill every `{{TOKEN}}`, write to the project root.
3. **Generate Layer 1:** for each folder that earns a room, read `templates/icm/CONTEXT.md`, fill it, write into that folder. Delete the Stage Contract section unless the folder is a pipeline stage.
4. **Verify:** grep for residual `{{`, confirm files written, and show the user the tree you created.
5. **Close:** suggest running `/folder-audit` to score the result.

## Token reference

`CLAUDE.md`: `{{PROJECT_NAME}}`, `{{ONE_LINE_DESCRIPTION}}`, `{{TASK_N}}`/`{{DIR_N}}`/`{{ENTRY_FILE_N}}` (routing rows), `{{BUILD_COMMAND}}`, `{{CONVENTION_N}}`, `{{ANTIPATTERN_1}}`, `{{OWNER}}`, `{{DATE}}`.
`CONTEXT.md`: `{{FOLDER_NAME}}`, `{{WHAT_THIS_FOLDER_IS_FOR}}`, `{{FILE}}`/`{{ROLE}}`, `{{WHAT_BELONGS_HERE}}`, `{{WHAT_DOES_NOT_BELONG_HERE}}`, plus Stage Contract tokens if kept.

Use today's date for `{{DATE}}` (ask the user or use the session date — never guess a different one).
